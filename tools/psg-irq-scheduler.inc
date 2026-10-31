; Experimental user-state producer. Only scalar registers cross SCF; the IRQ
; never reads the process map. X/Y stream cursors and U survive these calls.
; D/CC scratch. No interrupt masking. The system ring holds 256 complete
; four-byte events. Full => start once, then park and retry without dropping.
PSG_CLOCK_NAME fcc "/psgs"
      fcb 13
PSG_QUEUE_OPEN
      pshs x,y
      lda clockPath,u
      bpl PSG_QUEUE_OPENED
      ; This experimental descriptor owns only CoCoPSG in MPI slot 2.
      lda mpiPSG,u
      anda #3
      cmpa #1
      beq PSG_QUEUE_SLOT_OK
      ldb #E$BMode
      lbra PSG_CLOCK_ERROR
PSG_QUEUE_SLOT_OK
      leax PSG_CLOCK_NAME,pcr
      lda #UPDAT.
      os9 I$Open
      lbcs PSG_CLOCK_ERROR
      sta clockPath,u
PSG_QUEUE_OPENED
      clrb
      puls x,y,pc
PSG_CLOCK_START
      pshs x,y
      lbsr PSG_QUEUE_OPEN
      lbcs PSG_CLOCK_ERROR
      clra
      clrb
      std clockDeadline,u
      std clockDeadline+2,u
      std clockTarget,u
      std clockTarget+2,u
      std clockFraction,u
      std queueLast,u
      clr queueStarted,u
      clr clockBurst,u
      lbra PSG_CLOCK_RETURN
PSG_CLOCK_ERROR
      stb clockError,u
      lda #1
      sta abortFlag,u
      orcc #1
PSG_CLOCK_RETURN
      puls x,y,pc

; Final close cancels consumption and releases any remaining owned memory.
; Normal playback stops before restoring hardware and closes after unmapping.
; IOMan also invokes Close on fatal exit. Final detach removes registration.
PSG_CLOCK_CLOSE
      pshs cc,d,x,y
      lda clockPath,u
      bmi PSG_CLOCK_CLOSED
      os9 I$Close
      bcs PSG_CLOCK_CLOSED
      lda #$ff
      sta clockPath,u
PSG_CLOCK_CLOSED
      puls cc,d,x,y,pc

; All decoding, including zero-wait bursts, remains preemptible and yields
; after 32 commands. Abort is checked before each publication and sleep.
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
      andcc #$fe
PSG_CLOCK_DONE rts
PSG_CLOCK_ABORT
      orcc #1
      rts

; D=register:value. The saved event survives OS error B and all retry calls.
; Full is recoverable only in Loading/Running; underrun/stopped fail closed.
PSG_QUEUE_EVENT
      pshs x,y,d
PSG_QUEUE_RETRY
      tst abortFlag,u
      lbne PSG_QUEUE_ABORT
      ldy ,s
      ldx clockTarget+2,u
      lda clockPath,u
      ldb #$80
      os9 I$SetStt
      bcc PSG_QUEUE_ACCEPTED
      cmpb #E$DevBsy
      lbne PSG_QUEUE_ERROR
      tst queueStarted,u
      bne PSG_QUEUE_STATUS
      lbsr PSG_QUEUE_START
      lbcs PSG_QUEUE_ERROR
PSG_QUEUE_STATUS
      lda clockPath,u
      ldb #$80
      os9 I$GetStt
      lbcs PSG_QUEUE_ERROR
      cmpx #1
      bne PSG_QUEUE_FAILED
      ldx #2
      os9 F$Sleep
      lbcs PSG_QUEUE_ERROR
      bra PSG_QUEUE_RETRY
PSG_QUEUE_ACCEPTED
      ldd clockTarget+2,u
      std queueLast,u
      clrb
      leas 2,s
      puls x,y,pc
PSG_QUEUE_FAILED
      ldb #E$NotRdy
PSG_QUEUE_ERROR
      stb clockError,u
      lda #1
      sta abortFlag,u
PSG_QUEUE_ABORT
      orcc #1
      leas 2,s
      puls x,y,pc
PSG_QUEUE_START
      lda clockPath,u
      ldb #$81
      os9 I$SetStt
      bcs PSG_QUEUE_START_DONE
      inc queueStarted,u
PSG_QUEUE_START_DONE rts

; Natural EOF only: publish timed terminal, start a short stream, then drain.
; Signals cancel through common cleanup; never drain an error/abort path.
PSG_QUEUE_FINISH
      ldd #$ff00
      lbsr PSG_QUEUE_EVENT
      bcs PSG_QUEUE_FINISH_DONE
      pshs x,y
      tst queueStarted,u
      bne PSG_QUEUE_DRAIN
      bsr PSG_QUEUE_START
      lbcs PSG_CLOCK_ERROR
PSG_QUEUE_DRAIN
      tst abortFlag,u
      bne PSG_QUEUE_DRAIN_ABORT
      lda clockPath,u
      ldb #$80
      os9 I$GetStt
      lbcs PSG_CLOCK_ERROR
      cmpx #2
      beq PSG_QUEUE_DRAIN_DONE
      cmpx #1
      bne PSG_QUEUE_DRAIN_ERROR
      ldx #2
      os9 F$Sleep
      lbcs PSG_CLOCK_ERROR
      bra PSG_QUEUE_DRAIN
PSG_QUEUE_DRAIN_ERROR
      ldb #E$NotRdy
      lbra PSG_CLOCK_ERROR
PSG_QUEUE_DRAIN_DONE
      clrb
      puls x,y,pc
PSG_QUEUE_DRAIN_ABORT
      orcc #1
      puls x,y,pc
PSG_QUEUE_FINISH_DONE rts

; D=unsigned samples. Preserve exact fractional samples across waits/loops.
; Ceil only event deadlines. Every 4096 ticks of silence publish a no-op;
; one VGM wait adds <=90 ticks, so modular forward comparisons stay bounded.
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
      std clockTarget+2,u
      ldd clockFraction,u
      beq PSG_QUEUE_GAP
      ldd clockTarget+2,u
      addd #1
      std clockTarget+2,u
PSG_QUEUE_GAP
      ldd clockTarget+2,u
      subd queueLast,u
      cmpd #4096
      blo PSG_QUEUE_WAIT_DONE
      ldd #$fe00
      lbsr PSG_QUEUE_EVENT
      lbcs PSG_CLOCK_RETURN
PSG_QUEUE_WAIT_DONE
      lbsr PSG_CLOCK_BUDGET
      puls x,y,pc

; User-state adapters retain the original loader's register contract. Every
; block remains owned by /psgs until released, so F$Exit's I$Close can clear
; maps and free allocations even after a fatal signal. Only scalar block IDs
; and logical bases cross SCF; no pointer into player data is retained.
; B=1 -> D=allocated physical block; preserve X/Y/U, error B and carry.
PSG_OWN_ALLOC
      pshs x,y,u
      ldu <uRegImage
      lbsr PSG_QUEUE_OPEN
      bcs PSG_ALLOC_RETURN
      lda clockPath,u
      ldb #$84
      os9 I$SetStt
      bcs PSG_ALLOC_RETURN
      tfr x,d
PSG_ALLOC_RETURN
      puls x,y,u,pc
; X=owned block, B=1 -> U=logical base; preserve original D/X/Y on success.
PSG_OWN_MAP
      pshs d,x,y,u
      ldu <uRegImage
      lda clockPath,u
      ldb #$85
      os9 I$SetStt
      bcs PSG_RESOURCE_ERROR
      tfr y,u
      puls d,x,y
      leas 2,s
      rts
; U=logical base, B=1; preserve D/X/Y/U on success. Only remove an owned map.
PSG_OWN_CLEAR
      pshs d,x,y,u
      tfr u,x
      ldu <uRegImage
      lda clockPath,u
      ldb #$86
      os9 I$SetStt
      bra PSG_RESOURCE_RESULT
; X=owned physical block, B=1; driver rejects release while still mapped.
PSG_OWN_FREE
      pshs d,x,y,u
      ldu <uRegImage
      lda clockPath,u
      ldb #$87
      os9 I$SetStt
PSG_RESOURCE_RESULT
      bcc PSG_RESOURCE_RETURN
PSG_RESOURCE_ERROR
      stb 1,s
PSG_RESOURCE_RETURN
      puls d,x,y,u,pc
; Cancel delivery before user hardware restoration, retaining memory ownership
; until loader mappings and allocations have been released. Close is final.
PSG_QUEUE_STOP
      pshs cc,d,x,y
      lda clockPath,u
      bmi PSG_QUEUE_STOPPED
      ldb #$82
      os9 I$SetStt
PSG_QUEUE_STOPPED
      puls cc,d,x,y,pc
