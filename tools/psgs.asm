; Exclusive SCF descriptor for the opt-in streaming IRQ experiment.
H6309 equ 1
        include os9.d
        mod End,Name,Devic+Objct,ReEnt,Manager,Driver
        fcb UPDAT.+SHARE.,$07
        fdb $FF00
        fcb 1,DT.SCF
Manager fcs "SCF"
        ifdef GMC_DRIVER
Driver  fcs "GMCStream"
Name    fcs "gmcs"
        else
Driver  fcs "PSGStream"
Name    fcs "psgs"
        endc
        fcb 1
        emod
End     equ *
