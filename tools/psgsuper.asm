*******************************************************************************
* PSG playlist-stop experiment supervisor, ordinary OS-9 user process.
* Usage: psgsuper TICKS PATH
* Forks cctplaymt with "-psg 2 PATH", retains the child PID returned by F$Fork,
* sleeps TICKS, sends S$Intrpt to that child and waits for its exit. F$Send
* retries only E$USigP, at most three attempts with a two-tick F$Sleep between
* attempts. A child is not reaped until F$Wait, so its PID cannot be reused by
* the parent before the signal attempt. All results are reported as hex bytes.
* Inputs X=command tail, U=process data. No direct hardware or kernel changes.
* F$Fork copies the parameter byte area; U is restored after the call. All OS
* calls execute in user context with interrupts enabled. No signal handler.
*******************************************************************************
STDOUT EQU 1
CR EQU $0D
SP EQU $20
H6309 SET 1
        include os9.d
        MOD module_end,module_name,$11,$80,start,data_size
        org 0
child_pid RMB 1
send_status RMB 1
wait_status RMB 1
retry_count RMB 1
delay_ticks RMB 2
number_temp RMB 2
digit RMB 1
param_len RMB 2
params RMB 256
hexbuf RMB 3
stack_space RMB 512
data_size EQU .
module_name FCS "psgsuper"
        FCB 1
player_name FCS "cctplaymt"
prefix FCC "-psg 2 "
prefix_end EQU *
msg_fork FCC "SUP PID="
msg_fork_end EQU *
msg_send FCC " SEND="
msg_send_end EQU *
msg_wait FCC " WAIT="
msg_wait_end EQU *
msg_bad FCC "SUP ERROR"
        FCB CR
msg_bad_end EQU *
hex_digits FCC "0123456789ABCDEF"
start
        clr delay_ticks,U
        clr delay_ticks+1,U
skip_space
        lda ,X+
        cmpa #SP
        beq skip_space
parse_digit
        cmpa #'0'
        lblo bad
        cmpa #'9'
        lbhi bad
        suba #'0'
        sta digit,U
        ldd delay_ticks,U
        lslb
        rola
        lbcs bad
        std number_temp,U
        lslb
        rola
        lbcs bad
        lslb
        rola
        lbcs bad
        addd number_temp,U
        lbcs bad
        addb digit,U
        adca #0
        lbcs bad
        std delay_ticks,U
        lda ,X+
        cmpa #SP
        bne parse_digit
skip_path_space
        ldd delay_ticks,U
        cmpd #60                ; allow child to install its signal intercept
        lblo bad
path_spaces
        lda ,X+
        cmpa #SP
        beq path_spaces
        cmpa #CR
        lbeq bad
        leax -1,X               ; X points to the first path character
        lda #'-'
        sta params,U
        lda #'p'
        sta params+1,U
        lda #'s'
        sta params+2,U
        lda #'g'
        sta params+3,U
        lda #SP
        sta params+4,U
        lda #'2'
        sta params+5,U
        lda #SP
        sta params+6,U
        leay params+7,U
        clrb                    ; path length, including eventual CR
copy_path
        lda ,X+
        sta ,Y+
        incb
        cmpb #248
        lbhs bad
        cmpa #CR
        bne copy_path
path_done
        tfr Y,D
        pshs U
        subd ,S++
        subd #params
        std param_len,U
        ldy param_len,U
        pshs U
        leau params,U
        leax player_name,PCR
        ldd #$1100
        os9 F$Fork
        pshs CC
        puls CC,U
        lbcs exit_error
        sta child_pid,U
        lda #STDOUT
        leax msg_fork,PCR
        ldy #msg_fork_end-msg_fork
        os9 I$Write
        lda child_pid,U
        lbsr print_hex
        ldx delay_ticks,U
        os9 F$Sleep
        lbcs exit_error
        lda #3
        sta retry_count,U
send_again
        lda child_pid,U
        ldb #S$Intrpt
        os9 F$Send
        bcc send_ok
        stb send_status,U
        cmpb #E$USigP
        bne send_done
        dec retry_count,U
        beq send_done
        ldx #2
        os9 F$Sleep
        lbcs exit_error
        bra send_again
send_ok
        clr send_status,U
send_done
        lda #STDOUT
        leax msg_send,PCR
        ldy #msg_send_end-msg_send
        os9 I$Write
        lda send_status,U
        lbsr print_hex
        os9 F$Wait
        lbcs exit_error
        cmpa child_pid,U
        bne bad
        stb wait_status,U
        lda #STDOUT
        leax msg_wait,PCR
        ldy #msg_wait_end-msg_wait
        os9 I$Write
        lda wait_status,U
        lbsr print_hex
        lda #STDOUT
        leax newline,PCR
        ldy #1
        os9 I$Write
        ldb send_status,U
        os9 F$Exit
print_hex
        pshs D,X,Y
        leax hex_digits,PCR
        tfr A,B
        lsra
        lsra
        lsra
        lsra
        lda A,X
        sta hexbuf,U
        andb #15
        lda B,X
        sta hexbuf+1,U
        lda #STDOUT
        leax hexbuf,U
        ldy #2
        os9 I$Write
        puls D,X,Y,PC
newline FCB CR
bad
        lda #STDOUT
        leax msg_bad,PCR
        ldy #msg_bad_end-msg_bad
        os9 I$Write
        ldb #1
exit_error
        os9 F$Exit
        EMOD
module_end
