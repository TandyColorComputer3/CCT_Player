; Optional SCF clock driver, user-opened as /ctclock. No hardware writes.
; Init/Term run in system state; IRQ runs only through F$IRQ/F$VIRQ.
; Mutable storage is driver-local U. The five-byte VIRQ packet is followed
; by a big-endian 32-bit monotonic tick count. Counter wraps after >2 years.
; GetStat $80 returns an atomic, non-destructive snapshot in caller X:Y.
; No process pointer, parsing, allocation, I/O or signal delivery in IRQ.
H6309  equ 1
        include os9.d
        include scf.d
        mod End,Name,Drivr+Objct,ReEnt,Entry,MemSize
        fcb UPDAT.
Name    fcs "CCTClock"
        fcb 1
        org V.SCF
Packet  rmb 5
Ticks   rmb 4
MemSize equ .
Entry   lbra Init
        lbra Read
        lbra OK
        lbra GetStat
        lbra SetStat
        lbra Term
Poll    fcb 0,1,10
; F$IRQ uses D=status address, X=flip/mask/priority, Y=handler, U=storage.
; F$VIRQ uses D=initial count, X=nonzero add, Y=packet. Roll back on error.
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
        bsr RemoveIRQ
        puls cc,b,pc
; Remove the clock producer first, then its polling consumer. Do not free a
; live packet on error: return carry/error to IOMan, which owns driver storage.
Term    ldx #0
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
SetStat cmpa #SS.Close
        beq OK
Unknown comb
        ldb #E$UnkSvc
        rts
; Entry A=code,Y=path descriptor,U=driver data. Snapshot masks interrupts
; for four loads/stores only (<60 6809 cycles, <34us at 1.78MHz), restoring
; incoming CC before the ordinary success return. No OS call while masked.
GetStat cmpa #$80
        bne Unknown
        ldy PD.RGS,y
        pshs cc
        orcc #$50
        ldd Ticks,u
        std R$X,y
        ldd Ticks+2,u
        std R$Y,y
        puls cc
OK      clrb
        rts
; Poll-table dispatch already established the system map and U. Clear only
; our software pending bit. Worst path is bounded to four byte increments.
IRQ     lda #$80
        sta Packet+Vi.Stat,u
        inc Ticks+3,u
        bne OK
        inc Ticks+2,u
        bne OK
        inc Ticks+1,u
        bne OK
        inc Ticks,u
        bra OK
        emod
End     equ *
