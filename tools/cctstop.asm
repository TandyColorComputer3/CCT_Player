*******************************************************************************
* Graceful stop utility for the background CCT Player.
*
* Shell prints the child's decimal process ID when a command is launched with
* `&`. Run `cctstop PID` with that value. This ordinary re-entrant user process
* sends S$Intrpt with F$Send; cctplaymt's F$Icpt handler sets abortFlag, and the
* player then uses its normal PSG silence, mapping, RAM, path, MPI and PIA
* cleanup path. This is deliberately not a fatal process kill.
*
* Entry: X points at the OS-9 command tail; U is process-local data.
* F$Send inputs: A=target PID, B=S$Intrpt. Clobbers A, B, X, Y and flags.
* Decimal PID parsing is bounded to 1..255. Invalid input prints usage and exits
* with status 1. F$Send errors are returned unchanged as the process status.
*******************************************************************************

STDOUT          EQU   1
C$CR            EQU   $0D
C$LF            EQU   $0A
C$SPAC          EQU   $20
H6309           SET   1

        include os9.d

        MOD   MODULE_SIZE,moduleName,$11,$80,START_EXEC,data_size

START_MODULE
        org   0
targetPid       RMB   1
digitValue      RMB   1
digitSeen       RMB   1
data_size       EQU   .

moduleName      FCS   "cctstop"
        FCB   1

usageText       FCC   "Usage: cctstop PID"
        FCB   C$CR,C$LF
usageTextSize   EQU   *-usageText

START_EXEC
        clr   targetPid,U
        clr   digitSeen,U

CCTSTOP_SKIP_SPACE
        lda   ,X+
        cmpa  #C$SPAC
        beq   CCTSTOP_SKIP_SPACE
        cmpa  #C$CR
        beq   CCTSTOP_USAGE

CCTSTOP_DIGIT
        cmpa  #'0'
        blo   CCTSTOP_USAGE
        cmpa  #'9'
        bhi   CCTSTOP_USAGE
        suba  #'0'
        sta   digitValue,U
        lda   #1
        sta   digitSeen,U

        lda   targetPid,U
        ldb   #10
        mul                         ; D = previous PID * 10
        addb  digitValue,U
        adca  #0
        bne   CCTSTOP_USAGE         ; values above 255 are invalid
        stb   targetPid,U

        lda   ,X+
        cmpa  #C$CR
        beq   CCTSTOP_SEND
        cmpa  #C$SPAC
        bne   CCTSTOP_DIGIT

CCTSTOP_TRAILING_SPACE
        lda   ,X+
        cmpa  #C$SPAC
        beq   CCTSTOP_TRAILING_SPACE
        cmpa  #C$CR
        bne   CCTSTOP_USAGE

CCTSTOP_SEND
        tst   digitSeen,U
        beq   CCTSTOP_USAGE
        lda   targetPid,U
        beq   CCTSTOP_USAGE
        ldb   #S$Intrpt
        os9   F$Send
        bcs   CCTSTOP_EXIT          ; return the kernel's error code in B
        clrb
CCTSTOP_EXIT
        os9   F$Exit

CCTSTOP_USAGE
        lda   #STDOUT
        leax  usageText,PCR
        ldy   #usageTextSize
        os9   I$Write
        ldb   #1
        os9   F$Exit

        EMOD
MODULE_SIZE
