*******************************************************************************
* Bounded baseline supervisor: start diskload, then run synthetic30 five times.
* REAL_BENCH builds diskreal, which runs Arkanoid VGM, Ark1 CCT, Flicky CCT.
* IDLE_BENCH omits the workload child; COUNTER_BENCH uses countlong, the same
* counter cadence as timeload extended to cover all five sequential players.
* User process; no signal handling, direct device access, or interrupt masks.
* F$Fork copies each CR-terminated parameter area; A returns the child PID.
* F$Wait returns a child PID in A and its exit status in B. Each player is
* waited for before the next starts; the disk child must remain alive until
* all five complete, then is reaped normally. Unexpected PID/status fails.
* U is the process data pointer; F$Fork's parameter U is saved on stack.
* A/B/X/Y/CC are scratch. F$Exit receives B=0 on success, nonzero on error.
*******************************************************************************
H6309 SET 1
        include os9.d
        MOD module_end,module_name,$11,$80,start,data_size
        org 0
disk_pid RMB 1
child_pid RMB 1
remaining RMB 1
data_size EQU .
        ifdef REAL_BENCH
module_name FCS "diskreal"
        else
        ifdef IDLE_BENCH
module_name FCS "idlebench"
        else
        ifdef COUNTER_BENCH
module_name FCS "countbench"
        else
module_name FCS "diskbench"
        endc
        endc
        endc
        FCB 1
        ifdef COUNTER_BENCH
disk_name FCS "countlong"
        else
disk_name FCS "diskload"
        endc
player_name FCS "cctplaymt"
disk_params FCC "/d1/ark1.cct"
        FCB $0d
disk_params_end EQU *
player_params FCC "-psg 2 /d1/synthetic30.vgm"
        FCB $0d
player_params_end EQU *
        ifdef REAL_BENCH
arkanoid_params FCC "-psg 2 /d1/arkanoid.vgm"
        FCB $0d
arkanoid_end EQU *
ark1_params FCC "-psg 2 /d1/ark1.cct"
        FCB $0d
ark1_end EQU *
flicky_params FCC "-psg 2 /d1/flicky.cct"
        FCB $0d
flicky_end EQU *
        endc
msg_ok FCC "DISKBENCH OK"
        FCB $0d
msg_ok_end EQU *
msg_error FCC "DISKBENCH ERROR"
        FCB $0d
msg_error_end EQU *
start
        ifndef IDLE_BENCH
        pshs U
        leau disk_params,PCR
        leax disk_name,PCR
        ldy #disk_params_end-disk_params
        ldd #$1100
        os9 F$Fork
        pshs CC
        puls CC,U
        bcs fail
        sta disk_pid,U
        endc
        ifdef REAL_BENCH
        lda #3
        else
        lda #5
        endc
        sta remaining,U
next_player
        pshs U
        ifdef REAL_BENCH
        lda remaining,U
        cmpa #3
        beq first_real
        cmpa #2
        beq second_real
        leau flicky_params,PCR
        ldy #flicky_end-flicky_params
        bra real_ready
first_real
        leau arkanoid_params,PCR
        ldy #arkanoid_end-arkanoid_params
        bra real_ready
second_real
        leau ark1_params,PCR
        ldy #ark1_end-ark1_params
real_ready
        leax player_name,PCR
        else
        leau player_params,PCR
        leax player_name,PCR
        ldy #player_params_end-player_params
        endc
        ldd #$1100
        os9 F$Fork
        pshs CC
        puls CC,U
        bcs fail
        sta child_pid,U
        os9 F$Wait
        bcs fail
        cmpa child_pid,U
        bne fail
        tstb
        bne fail
        dec remaining,U
        bne next_player
        ifndef IDLE_BENCH
        os9 F$Wait
        bcs fail
        cmpa disk_pid,U
        bne fail
        tstb
        bne fail
        endc
        leax msg_ok,PCR
        ldy #msg_ok_end-msg_ok
        lda #1
        os9 I$Write
        clrb
        os9 F$Exit
fail
        leax msg_error,PCR
        ldy #msg_error_end-msg_error
        lda #1
        os9 I$Write
        ldb #1
        os9 F$Exit
        EMOD
module_end
