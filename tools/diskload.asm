*******************************************************************************
* Bounded, read-only floppy timing workload. Ordinary OS-9 user process.
* Usage: diskload /d1/file
* Repeat 230 open/read/close cycles, sleeping 61 ticks between cycles. X at
* entry points to the OS-9 path argument; U is process-local storage. The
* pathname is copied into the data area and terminated with CR. Each I$Open
* uses A=READ., X=path; I$Read uses A=path, X=buffer, Y=256; I$Close uses
* A=path; F$Sleep uses X=61. No writes to the disk, signal handler, or IRQ mask.
* The process exits with the first OS error in B, closing an acquired path
* after read errors. F$Exit does not return. A/B/X/Y/CC are scratch.
*******************************************************************************
H6309 SET 1
        include os9.d
        MOD module_end,module_name,$11,$80,start,data_size
        org 0
path    RMB 128
buffer  RMB 256
pathno  RMB 1
        ifdef LATENCY_STRESS
count   RMB 2               ; finite 920-read matrix workload, not production
        else
count   RMB 1
        endc
error   RMB 1
data_size EQU .
        ifdef CONTINUOUS_READ
* Same 230 read-only cycles (920 with LATENCY_STRESS), without sleeps. This is
* a finite disk burst; report its end separately from the player's end.
        ifdef LATENCY_STRESS
module_name FCS "diskstress"
        else
        ifdef STREAM_WORKLOAD
module_name FCS "diskburst"
        else
module_name FCS "diskbusy"
        endc
        endc
        else
        ifdef STREAM_WORKLOAD
module_name FCS "diskshort"
        else
module_name FCS "diskload"
        endc
        endc
        FCB 1
start
        leay path,U
        ldb #127
skip_space
        lda ,X+
        cmpa #$20
        beq skip_space
        leax -1,X
copy_path
        lda ,X+
        cmpa #$20
        beq path_end
        cmpa #$0d
        beq path_end
        sta ,Y+
        decb
        bne copy_path
        ldb #1
        os9 F$Exit
path_end
        lda #$0d
        sta ,Y
        ifdef LATENCY_STRESS
        ldd #920
        std count,U
        else
        ifdef STREAM_WORKLOAD
        ifdef CONTINUOUS_READ
        lda #128            ; bounded stress burst for streaming comparisons
        else
        lda #32             ; periodic read workload; no process termination
        endc
        else
        lda #230
        endc
        sta count,U
        endc
next_read
        lda #1              ; I$Open: read-only
        leax path,U
        os9 I$Open
        bcs exit_error
        sta pathno,U
        leax buffer,U
        ldy #256
        os9 I$Read
        bcs read_error
        lda pathno,U
        os9 I$Close
        bcs exit_error
        ifdef LATENCY_STRESS
        ldd count,U
        subd #1
        std count,U
        else
        dec count,U
        endc
        beq completed
        ifndef CONTINUOUS_READ
        ldx #61
        os9 F$Sleep
        bcs exit_error
        endc
        bra next_read
read_error
        stb error,U         ; retain I$Read error across I$Close
        lda pathno,U
        os9 I$Close
        ldb error,U
exit_error
        os9 F$Exit
completed
        clrb
        os9 F$Exit
        EMOD
module_end
