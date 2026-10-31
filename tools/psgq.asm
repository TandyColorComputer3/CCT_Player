; Exclusive SCF descriptor for the opt-in fixed-stream IRQ experiment.
H6309 equ 1
        include os9.d
        mod End,Name,Devic+Objct,ReEnt,Manager,Driver
        fcb UPDAT.+SHARE.,$07
        fdb $FF00
        fcb 1,DT.SCF
Manager fcs "SCF"
Driver  fcs "PSGQueue"
Name    fcs "psgq"
        fcb 1
        emod
End     equ *
