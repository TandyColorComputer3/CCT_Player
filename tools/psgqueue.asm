; Experimental fixed-stream CoCoPSG driver. HD6309 EOU SCF system context.
; Queue storage belongs to IOMan, never to the producer's logical map.
; One owner path; no second writer. No refill while Running, so complete
; four-byte records are published before IRQ consumption can begin.
; SetStat $80: append X=tick (0..32767), Y=register:value (reg0..13, FF=end).
; $81 starts preloaded stream; $82 stops/mutes. GetStat $80: X=state,
; Y=remaining records; $81: X=over-budget ticks,Y=underruns.
; States 0=loading,1=running,2=complete,3=underrun,4=stopped.
; IRQ consumes <=8 PSG writes per tick, retains overflow for the next tick.
; No OS calls, process pointers, allocation, parser or wait in IRQ context.
H6309 equ 1
        include os9.d
        include scf.d
        mod End,Name,Drivr+Objct,ReEnt,Entry,MemSize
        fcb UPDAT.+SHARE.
Name    fcs "PSGQueue"
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
Queue   rmb 1024
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
Init    lda #$80
        sta Packet+Vi.Stat,u
        ldd #1
        std Packet+Vi.Rst,u
        leax Packet+Vi.Stat,u
        tfr x,d
        leax Poll,pcr
        leay IRQ,pcr
        os9 F$IRQ
        bcs Return
        ldd #1
        ldx #1
        leay Packet,u
        os9 F$VIRQ
        bcc Return
        pshs b,cc
        lbsr RemoveIRQ
        puls cc,b,pc
; Stop under saved CC, remove producer before consumer. Return errors to
; IOMan rather than freeing a live registration. D/X/Y/CC scratch, U retained.
Term    lbsr Stop
        ldx #0
        leay Packet,u
        os9 F$VIRQ
        bcs Return
RemoveIRQ
        leax Packet+Vi.Stat,u
        tfr x,d
        ldx #0
        leay IRQ,pcr
        os9 F$IRQ
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
        cmpa #$82
        beq Stop
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
Close   bsr Stop
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
        ldd #$073f
        lbsr WritePSG
        puls cc
        lbra OK
; Append via caller register image supplied by SCF. No user-pointer copying.
; IRQ never consumes in state0. Each entry: big-endian tick, reg, value.
Append  tst State,u
        lbne Busy
        tst Sealed,u
        lbne Busy
        ldd Count,u
        cmpd #256
        lbhs Busy
        ldy PD.RGS,y
        ldd R$X,y
        lbmi Invalid
        cmpd Last,u
        lblo Invalid
        lda R$Y,y
        cmpa #$ff
        beq Valid
        cmpa #13
        lbhi Invalid
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
        lbra OK
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
; Budget is eight register/value transactions, not eight unbounded groups.
; Handler wall time is measured externally before accepting its budget.
IRQ     lda #$80
        sta Packet+Vi.Stat,u
        lda State,u
        cmpa #1
        lbne OK
        ldd Ticks,u
        addd #1
        std Ticks,u
        lda #8
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
        ldd 2,x
        bsr WritePSG
        inc Head,u
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
        ldd #$073f
        bsr WritePSG
        lbra OK
; D=register/value; preserve X/Y/U and live MPI. IRQ already masks IRQ; save
; and restore CC to also bound FIRQ during selection. Same select/data spacing
; as the existing player. Changes only SCS bits, never CART/audio routing.
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
        emod
End     equ *
