; Experimental streaming CoCoPSG/GMC driver. HD6309 EOU SCF system context.
; Queue storage belongs to IOMan, never to the producer's logical map.
; One owner path; one producer. Atomic Append may refill while Running.
; SetStat $80: append X=modulo tick, Y=register:value. CoCoPSG uses
; registers 0..13; GMC uses register 0 and one raw command byte in value.
; FE=no-op and FF=end in either build.
; $81 starts preloaded stream; $82 stops/mutes. GetStat $80: X=state,
; Y=remaining records; $81: X=over-budget ticks,Y=underruns.
; Resource SetStat $84/$85/$86/$87: allocate/map/clear/free one owned block.
; Only the opening process may use this path; cctirq never forks with it open.
; States 0=loading,1=running,2=complete,3=underrun,4=stopped.
; IRQ consumes <=16 records/tick, including no-op markers.
; Overflow stays queued for the next tick.
; No OS calls, process pointers, allocation, parser or wait in IRQ context.
; Separate module; the original PSGQueue remains eight writes/tick.
        ifndef IRQ_BUDGET
IRQ_BUDGET equ 16
        endc
H6309 equ 1
        include os9.d
        include scf.d
        mod End,Name,Drivr+Objct,ReEnt,Entry,MemSize
        fcb UPDAT.+SHARE.
        ifdef GMC_DRIVER
Name    fcs "GMCStream"
        else
Name    fcs "PSGStream"
        endc
        fcb 1
        org V.SCF
Packet  rmb 5
Owner   rmb 2
Ticks   rmb 2
Count   rmb 2
Head    rmb 1
Tail    rmb 1
State   rmb 1
Last    rmb 2
Budgets rmb 2
Unders  rmb 2
Sealed  rmb 1
Limit   rmb 1
PreviousControl rmb 1
Queue   rmb 1024
OwnedBlocks rmb 256        ; allocation ownership, never process pointers
OwnedMaps rmb 16            ; physical block+1 for each owned logical slot
IRQInstalled rmb 1       ; successful registrations only; not mere attempts
TimerInstalled rmb 1
        ifdef IRQ_FAIL_ALLOC
AllocationAttempts rmb 1   ; diagnostic only; production storage unchanged
        endc
MemSize equ .
Entry   lbra Init
        lbra Read
        lbra Unknown
        lbra GetStat
        lbra SetStat
        lbra Term
Poll    fcb 0,1,10
; System Init: F$IRQ registers packet status/mask/handler/storage; F$VIRQ
; schedules its pending bit every video tick. Roll back IRQ if VIRQ fails.
Init
        clr IRQInstalled,u
        clr TimerInstalled,u
        ifdef IRQ_FAIL_INIT
        ; Diagnostic: fail before registering either service. No kernel patch.
        comb
        ldb #E$NoRAM
        rts
        endc
        ifdef IRQ_FAIL_ALLOC
        clr AllocationAttempts,u
        endc
        lda #$80
        sta Packet+Vi.Stat,u
        ldd #1
        std Packet+Vi.Rst,u
        leax Packet+Vi.Stat,u
        tfr x,d
        leax Poll,pcr
        leay IRQ,pcr
        os9 F$IRQ
        lbcs Return
        inc IRQInstalled,u
        ldd #1
        ldx #1
        leay Packet,u
        ifdef IRQ_FAIL_VIRQ
        ; Diagnostic: exercise the real rollback after successful F$IRQ.
        comb
        ldb #E$NoRAM
        else
        os9 F$VIRQ
        endc
        bcc InitTimerReady
        pshs b,cc
        lbsr RemoveIRQ
        puls cc,b,pc
InitTimerReady
        inc TimerInstalled,u
        clrb
        rts
; Stop under saved CC, remove producer before consumer. Return errors to
; IOMan rather than freeing a live registration. D/X/Y/CC scratch, U retained.
Term    ldd Owner,u
        beq TermTimer
        lbsr Stop            ; Init failure never owned audio; do not mute it
TermTimer
        tst TimerInstalled,u
        beq RemoveIRQ
        ldx #0
        leay Packet,u
        os9 F$VIRQ
        lbcs Return
        clr TimerInstalled,u
RemoveIRQ
        tst IRQInstalled,u
        beq RemoveDone
        leax Packet+Vi.Stat,u
        tfr x,d
        ldx #0
        leay IRQ,pcr
        os9 F$IRQ
        bcs Return
        clr IRQInstalled,u
RemoveDone
        clrb
Return  rts
Read    comb
        ldb #E$EOF
        rts
Unknown comb
        ldb #E$UnkSvc
        rts
Busy    comb
        ldb #E$DevBsy
        rts
Invalid comb
        ldb #E$BMode
        rts
; A=status, Y=system path descriptor, U=driver storage. SCF calls SS.Open
; and SS.Close; owner is a system path pointer, not process-local memory.
SetStat cmpa #SS.Open
        beq Open
        cmpy Owner,u
        lbne Busy
        cmpa #SS.Close
        beq Close
        cmpa #$84
        lbeq AllocateBlock
        cmpa #$85
        lbeq MapBlock
        cmpa #$86
        lbeq ClearBlock
        cmpa #$87
        lbeq FreeBlock
        cmpa #$82
        lbeq Stop
        cmpa #$80
        lbeq Append
        cmpa #$81
        lbne Unknown
        tst State,u
        lbne Busy
        ldd Count,u
        beq Invalid
        pshs cc
        orcc #$50
        ldd #$ffff          ; first serviced callback establishes tick zero
        std Ticks,u
        lda #1
        sta State,u
        puls cc
OK      clrb
        rts
Open    ldd Owner,u
        lbne Busy
        ifndef GMC_DRIVER
        lbsr ClaimControl
        endc
        sty Owner,u
        clra
        clrb
        std Ticks,u
        std Count,u
        std Head,u
        std Budgets,u
        std Unders,u
        std Last,u
        sta State,u
        sta Sealed,u
        lbra OK
Close   lbsr Stop
        ifndef GMC_DRIVER
        lbsr ReleaseControl
        endc
        lbsr ReleaseMemory
        lbcs Return
        clra
        clrb
        std Owner,u
        rts
; System context: masks only state change and a single mute transaction.
; No OS call or queue loop while masked. Incoming CC restored.
Stop    pshs cc
        orcc #$50
        lda #4
        sta State,u
        ifdef GMC_DRIVER
        lbsr MuteChip
        else
        ldd #$073f
        lbsr WritePSG
        endc
        puls cc
        lbra OK
; Append via caller register image supplied by SCF. No user-pointer copying.
; IRQ never consumes in state0. Each entry: big-endian tick, reg, value.
 ; Append owns the short critical section from validation through publication.
; System context, X/Y/D scratch; U retained. Save incoming CC on every exit.
; Four bytes are copied before Count; no OS call or PSG write while masked.
; Modular forward deadlines must differ by less than 32768 ticks. Producer
; inserts FE no-op records during long silences to preserve this bound.
Append  pshs cc
        orcc #$50
AppendLocked
        lda State,u
        cmpa #1
        bhi AppendBusy
        tst Sealed,u
        bne AppendBusy
        ldd Count,u
        cmpd #256
        bhs AppendBusy
        ldy PD.RGS,y
        ldd R$X,y
        subd Last,u
        bmi AppendInvalid
        lda R$Y,y
        cmpa #$fe
        bhs Valid
        ifdef GMC_DRIVER
        tsta
        bne AppendInvalid
        else
        cmpa #13
        bhi AppendInvalid
        endc
Valid   ldd R$X,y
        std Last,u
        clra
        ldb Tail,u
        lslb
        rola
        lslb
        rola
        leax Queue,u
        leax d,x
        ldd R$X,y
        std ,x
        ldd R$Y,y
        std 2,x
        cmpa #$ff
        bne Publish
        inc Sealed,u
Publish inc Tail,u
        ldd Count,u
        addd #1
        std Count,u
AppendUnlock
        puls cc
        lbra OK
AppendBusy
        puls cc
        lbra Busy
AppendInvalid
        puls cc
        lbra Invalid
; Atomic status snapshot: <=4 data word accesses plus register-frame stores.
GetStat cmpa #$80
        beq Status
        cmpa #$81
        lbne Unknown
        ldy PD.RGS,y
        pshs cc
        orcc #$50
        ldd Budgets,u
        std R$X,y
        ldd Unders,u
        bra StoreY
Status  ldy PD.RGS,y
        pshs cc
        orcc #$50
        clra
        ldb State,u
        std R$X,y
        ldd Count,u
StoreY  std R$Y,y
        puls cc
        lbra OK
; IRQ entry U=driver storage, system map installed by kernel poll dispatcher.
; Budget counts register/value transactions, not unbounded groups.
; Handler wall time is measured externally before accepting its budget.
IRQ     lda #$80
        sta Packet+Vi.Stat,u
        lda State,u
        cmpa #1
        lbne OK
        ldd Ticks,u
        addd #1
        std Ticks,u
        lda #IRQ_BUDGET
        sta Limit,u
Next    ldd Count,u
        beq Underrun
        clra
        ldb Head,u
        lslb
        rola
        lslb
        rola
        leax Queue,u
        leax d,x
        ldd Ticks,u
        subd ,x
        lbmi OK
        lda 2,x
        cmpa #$ff
        beq Complete
        tst Limit,u
        beq Budget
        dec Limit,u
        cmpa #$fe
        beq Consume
        ldd 2,x
        lbsr WritePSG
Consume inc Head,u
        ldd Count,u
        subd #1
        std Count,u
        bra Next
Budget  ldd Budgets,u
        addd #1
        std Budgets,u
        lbra OK
Underrun
        tst Limit,u
        beq Budget
        ldd Unders,u
        addd #1
        std Unders,u
        lda #3
        bra EndPlay
Complete
        tst Limit,u
        beq Budget
        inc Head,u
        ldd Count,u
        subd #1
        std Count,u
        lda #2
EndPlay sta State,u
        ifdef GMC_DRIVER
        lbsr MuteChip
        else
        ldd #$073f
        lbsr WritePSG
        endc
        lbra OK
; Scalar resource services, system process context only. Each successful OS
; call is recorded before returning to user state, so a fatal signal cannot
; strand an unrecorded allocation. No IRQ mask or handler use. IOMan storage
; owns bookkeeping; the caller never passes a process-local data pointer.
; $84 allocates one 8 KiB block, returning X. $85 maps owned block X, returns
; Y=logical base. $86 clears logical base X. $87 frees unmapped owned block X.
AllocateBlock
        ifdef IRQ_FAIL_ALLOC
        ; Diagnostic: one real block can be owned before the next request
        ; fails. This exercises cleanup without starving unrelated processes.
        inc AllocationAttempts,u
        lda AllocationAttempts,u
        cmpa #2
        blo AllocateAllowed
        comb
        ldb #E$NoRAM
        rts
AllocateAllowed
        endc
        ldy PD.RGS,y
        pshs y
        ldb #1
        os9 F$AllRAM
        bcs ResourceReturn
        tfr d,x
        leay OwnedBlocks,u
        tfr x,d
        leay d,y
        lda #1
        sta ,y
        ldy ,s
        stx R$X,y
        clrb
ResourceReturn
        puls y,pc
MapBlock
        ldy PD.RGS,y
        ldx R$X,y
        cmpx #256
        lbhs Invalid
        tfr x,d
        leax OwnedBlocks,u
        lda d,x
        lbeq Invalid
        ldx R$X,y
        pshs y,u
        ldb #1
        os9 F$MapBlk
        bcs MapError
        tfr u,x
        puls u,y
        stx R$Y,y
        tfr x,d
        lsra
        lsra
        lsra
        lsra
        leax OwnedMaps,u
        leax a,x
        ldd R$X,y
        addd #1
        std ,x
        lbra OK
MapError
        puls u,y,pc
ClearBlock
        ldy PD.RGS,y
        ldx R$X,y
        tfr x,d
        tstb
        lbne Invalid
        bita #$1f
        lbne Invalid
        lsra
        lsra
        lsra
        lsra
        leay OwnedMaps,u
        leay a,y
        ldd ,y
        lbeq Invalid
        pshs y,u
        tfr x,u
        ldb #1
        os9 F$ClrBlk
        puls u,y
        lbcs MemoryReturn
        clra
        clrb
        std ,y
        lbra OK
FreeBlock
        ldy PD.RGS,y
        ldx R$X,y
        cmpx #256
        lbhs Invalid
        leay OwnedBlocks,u
        tfr x,d
        leay d,y
        tst ,y
        lbeq Invalid
        pshs x,y
        tfr x,d
        addd #1
        ldx #8
        leay OwnedMaps,u
FreeCheck
        cmpd ,y++
        beq FreeBusy
        leax -1,x
        bne FreeCheck
        puls x,y
        pshs y
        ldb #1
        os9 F$DelRAM
        puls y
        lbcs MemoryReturn
        clr ,y
        lbra OK
FreeBusy
        puls x,y
        lbra Busy
; Close runs for the owning path, including F$Exit's path cleanup. Remove all
; recorded mappings through F$ClrBlk before freeing any allocation. The same
; current process owns these mappings; this exclusive path is never forked.
; On an OS error retain ownership/storage instead of freeing mapped RAM.
ReleaseMemory
        ldx #0
ReleaseMapNext
        leay OwnedMaps,u
        tfr x,d
        ldd d,y
        beq ReleaseMapSkip
        pshs x,u
        tfr x,d
        lsrb
        rora
        lsrb
        rora
        lsrb
        rora
        lsrb
        rora
        tfr d,u
        ldb #1
        os9 F$ClrBlk
        puls u,x
        lbcs MemoryReturn
        leay OwnedMaps,u
        tfr x,d
        leay d,y
        clra
        clrb
        std ,y
ReleaseMapSkip
        leax 2,x
        cmpx #16
        blo ReleaseMapNext
        ldx #0
ReleaseBlockNext
        leay OwnedBlocks,u
        tfr x,d
        tst d,y
        beq ReleaseBlockSkip
        pshs x
        ldb #1
        os9 F$DelRAM
        puls x
        lbcs MemoryReturn
        leay OwnedBlocks,u
        tfr x,d
        clr d,y
ReleaseBlockSkip
        leax 1,x
        cmpx #256
        blo ReleaseBlockNext
        clrb
MemoryReturn rts

; System ownership transaction, bounded and saved-CC. Open captures control
; before user setup; Close restores it even after forced process termination.
; No OS calls; preserve X/Y/U, live MPI selection and incoming interrupt masks.
        ifndef GMC_DRIVER
ClaimControl
        pshs cc
        orcc #$50
        lda >$ff7f
        pshs a
        anda #$fc
        ora #1
        sta >$ff7f
        lda >$ff5d
        sta PreviousControl,u
        bra ControlReturn
ReleaseControl
        pshs cc
        orcc #$50
        lda >$ff7f
        pshs a
        anda #$fc
        ora #1
        sta >$ff7f
        lda PreviousControl,u
        sta >$ff5d
ControlReturn
        puls a
        sta >$ff7f
        puls cc,pc
; D=register/value; preserve X/Y/U and live MPI. IRQ already masks IRQ; save
; and restore CC to also bound FIRQ during selection. Same select/data spacing
; as the existing player. Changes only SCS bits, never CART/audio routing.
        endc
        ifdef GMC_DRIVER
; System/IRQ context: D=00:raw command. Select GMC SCS slot 1 only for
; one write, then restore live MPI and CC. Preserve D/X/Y/U. No OS call.
WritePSG
        pshs cc,d
        orcc #$50
        lda >$ff7f
        pshs a
        anda #$fc
        sta >$ff7f
        ldb 3,s
        stb >$ff41
        lbrn WritePSG
        lbrn WritePSG
        puls a
        sta >$ff7f
        puls cc,d,pc
; Four individual attenuation latches; preserve ordering and live MPI.
MuteChip
        ldd #$009f
        bsr WritePSG
        ldd #$00bf
        bsr WritePSG
        ldd #$00df
        bsr WritePSG
        ldd #$00ff
        lbra WritePSG
        else
WritePSG
        pshs cc,d
        orcc #$50
        lda >$ff7f
        pshs a
        anda #$fc
        ora #1
        sta >$ff7f
        ldd 2,s
        sta >$ff5e
        lbrn WritePSG
        stb >$ff5f
        puls a
        sta >$ff7f
        puls cc,d,pc
        endc
        emod
End     equ *
