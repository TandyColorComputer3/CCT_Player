; Optional SCF descriptor for CCTClock. No physical timer/port is accessed.
H6309  equ 1
        include os9.d
        mod End,Name,Devic+Objct,ReEnt,Manager,Driver
        fcb UPDAT.,$07
        fdb $FF00
        fcb 1,DT.SCF
Manager fcs "SCF"
Driver  fcs "CCTClock"
Name    fcs "ctclock"
        fcb 1
        emod
End     equ *
