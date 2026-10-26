*******************************************************************************
* CoCoPSG/YM2149 hardware probe for NitrOS-9 Level II
*
* This ordinary re-entrant user process bypasses the CCT/VGM loader. It selects
* MPI slot 2, snapshots the shared MPI/PIA/CoCoPSG state, programs channel A for
* a recognizable nominal 500 Hz square wave, sleeps for 120 NTSC OS-9
* ticks, silences the channel, and restores every saved register.
*
* Process context: user state. No interrupt handler and no interrupt masking.
* Entry: U points at process-local data. Clobbers A, B, X and condition codes.
* F$Sleep input: X=120 ticks. Any sleep error still takes the cleanup path.
* Hardware ownership is intentionally limited to this two-second diagnostic;
* do not run another cartridge-audio program concurrently.
*******************************************************************************

MPI_REG          EQU   $FF7F
PIA_SOUND        EQU   $FF23
PSG_CONTROL      EQU   $FF5D
PSG_SELECT       EQU   $FF5E
PSG_DATA         EQU   $FF5F

H6309            SET   1

        include os9.d

        MOD   MODULE_SIZE,moduleName,$11,$80,START_EXEC,data_size

START_MODULE
        org   0
savedMPI        RMB   1
savedPIA        RMB   1
savedControl    RMB   1
savedToneLow    RMB   1
savedToneHigh   RMB   1
savedMixer      RMB   1
savedVolume     RMB   1
data_size       EQU   .

moduleName      FCS   "psgprobe"
        FCB   1

START_EXEC
        lda   >MPI_REG
        sta   savedMPI,U
        anda  #$F0
        ora   #1              ; MPI slot 2 is encoded as zero-based slot 1
        sta   >MPI_REG

        lda   >PIA_SOUND
        sta   savedPIA,U
        lda   >PSG_CONTROL
        sta   savedControl,U

        lda   #0
        lbsr  PSG_READ_REG
        sta   savedToneLow,U
        lda   #1
        lbsr  PSG_READ_REG
        sta   savedToneHigh,U
        lda   #7
        lbsr  PSG_READ_REG
        sta   savedMixer,U
        lda   #8
        lbsr  PSG_READ_REG
        sta   savedVolume,U

        clra                  ; CoCoPSG control value 0 selects its 2 MHz clock
        sta   >PSG_CONTROL
        lda   savedPIA,U
        ora   #%00001000      ; route cartridge sound through CoCo audio
        sta   >PIA_SOUND

        lda   #7
        ldb   #$3E            ; tone A on; tone B/C and all noise off
        lbsr  PSG_WRITE_REG
        lda   #8
        ldb   #$0F            ; channel A fixed maximum volume
        lbsr  PSG_WRITE_REG
        lda   #0
        ldb   #250            ; 2 MHz / (16 * 250) = 500 Hz
        lbsr  PSG_WRITE_REG
        lda   #1
        clrb
        lbsr  PSG_WRITE_REG

        ldx   #120            ; nominally two seconds at the NTSC 60 Hz tick
        os9   F$Sleep

PSG_PROBE_CLEANUP
        lda   #8
        clrb                  ; silence before restoring the caller's state
        lbsr  PSG_WRITE_REG
        lda   #0
        ldb   savedToneLow,U
        lbsr  PSG_WRITE_REG
        lda   #1
        ldb   savedToneHigh,U
        lbsr  PSG_WRITE_REG
        lda   #7
        ldb   savedMixer,U
        lbsr  PSG_WRITE_REG
        lda   #8
        ldb   savedVolume,U
        lbsr  PSG_WRITE_REG

        lda   savedControl,U
        sta   >PSG_CONTROL
        lda   savedPIA,U
        sta   >PIA_SOUND
        lda   savedMPI,U
        sta   >MPI_REG
        clrb                  ; successful OS-9 process exit status
        os9   F$Exit

* Read one YM2149 register. Input A=register; output A=value. User context.
* The never-taken long branch supplies the same short bus settling delay used
* by the original player. No OS call and no interrupt masking.
PSG_READ_REG
        sta   >PSG_SELECT
        lbrn  PSG_READ_REG
        lda   >PSG_DATA
        rts

* Write one YM2149 register. Input A=register, B=value. User context. The
* critical hardware sequence is bounded and remains interruptible.
PSG_WRITE_REG
        sta   >PSG_SELECT
        lbrn  PSG_WRITE_REG
        stb   >PSG_DATA
        rts

        EMOD
MODULE_SIZE
