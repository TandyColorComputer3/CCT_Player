; User-process elapsed-time scheduler. X/Y stream cursors and U are preserved;
; D and condition codes are scratch except where a routine says otherwise.
; /ctclock is optional and must be loaded; missing clock fails closed rather
; than silently reverting to CPU-cycle timing. No privileged calls or masks.
; Clock reports ticks independent of scheduling; default NTSC is nominal 60Hz.
; No per-wait rounding: exact sample remainders are retained across all waits
; and loop iterations; only the current delivery deadline is rounded upward.
PSG_CLOCK_NAME fcc "/ctclock"
      fcb 13
PSG_CLOCK_START
      pshs x,y
      leax PSG_CLOCK_NAME,pcr
      lda #UPDAT.
      os9 I$Open
      lbcs PSG_CLOCK_ERROR
      sta clockPath,u
      ldb #$80
      os9 I$GetStt
      lbcs PSG_CLOCK_ERROR
      stx clockDeadline,u
      sty clockDeadline+2,u
      clr clockFraction,u
      clr clockFraction+1,u
      clr clockBurst,u
      clrb
      bra PSG_CLOCK_RETURN
PSG_CLOCK_ERROR
      stb clockError,u
      lda #1
      sta abortFlag,u
      orcc #1
PSG_CLOCK_RETURN
      puls x,y,pc

; Close only our owned clock path, once, in user state. I$Close lets IOMan
; terminate the driver when its final attachment closes; driver tears down
; VIRQ before IRQ. Preserve register/CC state for caller's existing cleanup.
PSG_CLOCK_CLOSE
      pshs cc,d,x,y
      lda clockPath,u
      bmi PSG_CLOCK_CLOSED
      os9 I$Close
      bcs PSG_CLOCK_CLOSED ; retain ownership if close failed; final exit retries
      lda #$FF
      sta clockPath,u
PSG_CLOCK_CLOSED
      puls cc,d,x,y,pc

; Every 32 commands at most, yield through F$Sleep X=1. Prevents a stream of
; overdue or zero-wait events monopolizing its time slice. All PSG writes are
; retained. Sleep is not a timestamp: always re-read clock in the wait loop.
PSG_CLOCK_BUDGET
      inc clockBurst,u
      lda clockBurst,u
      cmpa #32
      blo PSG_CLOCK_OK
      clr clockBurst,u
      pshs x
      ldx #1
      os9 F$Sleep
      puls x
      bcs PSG_CLOCK_DONE
PSG_CLOCK_OK
      tst abortFlag,u
      bne PSG_CLOCK_ABORT
      andcc #$FE
PSG_CLOCK_DONE rts
PSG_CLOCK_ABORT
      orcc #1
      rts

; D=unsigned VGM wait (0..65535). Divide before adding remainder so 16-bit
; addition cannot overflow. At most 89 subtractions at NTSC; no IRQ masking.
; Deadline and clock are modulo-32-bit ticks. Each preceding wait completes
; before another is added, so a future target is at most 90 ticks away.
; The sign/low-word comparison below relies on that bound (it is not a
; general arbitrary-positive-distance comparator). Lateness must remain
; below 2^31 ticks (>1 year at 60Hz) for the sign test to survive rollover.
PSG_CLOCK_WAIT
      pshs x,y
      ldx #0
PSG_CLOCK_DIVIDE
      cmpd #PSG_SAMPLES_PER_TICK
      blo PSG_CLOCK_REMAINDER
      subd #PSG_SAMPLES_PER_TICK
      leax 1,x
      bra PSG_CLOCK_DIVIDE
PSG_CLOCK_REMAINDER
      addd clockFraction,u
      cmpd #PSG_SAMPLES_PER_TICK
      blo PSG_CLOCK_STORE
      subd #PSG_SAMPLES_PER_TICK
      leax 1,x
PSG_CLOCK_STORE
      std clockFraction,u
      tfr x,d
      addd clockDeadline+2,u
      std clockDeadline+2,u
      ldd clockDeadline,u
      adcb #0
      adca #0
      std clockDeadline,u
      std clockTarget,u
      ldd clockDeadline+2,u
      std clockTarget+2,u
      ldd clockFraction,u
      beq PSG_CLOCK_CHECK
      ldd clockTarget+2,u
      addd #1
      std clockTarget+2,u
      ldd clockTarget,u
      adcb #0
      adca #0
      std clockTarget,u
PSG_CLOCK_CHECK
      tst abortFlag,u
      bne PSG_CLOCK_WAIT_ABORT
      lda clockPath,u
      ldb #$80
      os9 I$GetStt
      lbcs PSG_CLOCK_ERROR
      ; Save the snapshot on our stack; subtraction low then high propagates
      ; borrow. No CPU work estimate or F$Sleep count changes the timeline.
      pshs x,y
      ldd clockTarget+2,u
      subd 2,s
      std 2,s
      ldd clockTarget,u
      sbcb 1,s
      sbca ,s
      leas 2,s
      bmi PSG_CLOCK_DUE_POP
      bne PSG_CLOCK_FUTURE_POP
      ldd ,s
      beq PSG_CLOCK_DUE_POP
PSG_CLOCK_FUTURE_POP
      leas 2,s
      ; X=2 parks until a clock tick rather than spinning through X=1
      ; reschedules when otherwise idle. This is only a wakeup request; a
      ; late or early wake is resolved by the next atomic clock snapshot.
      ldx #2
      os9 F$Sleep
      lbcs PSG_CLOCK_ERROR
      clr clockBurst,u
      bra PSG_CLOCK_CHECK
PSG_CLOCK_DUE_POP
      leas 2,s
      lbsr PSG_CLOCK_BUDGET
      puls x,y,pc
PSG_CLOCK_WAIT_ABORT
      orcc #1
      puls x,y,pc
