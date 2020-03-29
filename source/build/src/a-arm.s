        .file "a-arm.s"
        .text

        .global arm_frameoffset
        .global arm_bpl
        .global arm_glogy
        .global arm_tilesize
        .global arm_gtrans
        .global arm_transmode

        .macro FUNCNAME NAME
0:
        .asciz "\NAME"
        .align
1:
        .word 0xff000000 + (1b - 0b)
        .endm

        @ Macro for rendering a column of 4 pixels to a scratchpad on the stack
        @ (power-of-two texture size)
        @
        @ X = column number within scratchpad
        @ W = width of scratchpad
        @ INC = increment for line list pointer
        @ TAIL = optional instruction to insert near end
        @
        .macro COLUMN4 X W INC TAIL
        @ Round-robin loop scheduling is neatest for ARM11, and luckily
        @ we have enough registers
        mov     a1, v5, lsr a3 @ Row 0
        add     v5, v5, ip
         mov     a2, v5, lsr a3 @ Row 1
        ldrb    a1, [v6, a1] @ issue texture loads as soon as possible, as that's most likely to stall
         add     v5, v5, ip
         ldrb    a2, [v6, a2]
          mov     v1, v5, lsr a3 @ Row 2
          add     v5, v5, ip
           mov     v2, v5, lsr a3 @ Row 3
          ldrb    v1, [v6, v1]
           add     v5, v5, ip
           ldrb    v2, [v6, v2]
            str     v5, [v3], #\INC @ Write back new vpos
        ldrb    a1, [lr, a1]
         ldrb    a2, [lr, a2]
          ldrb    v1, [lr, v1]
           ldrb    v2, [lr, v2]
        strb    a1, [sp, #\X]
         strb    a2, [sp, #\X+\W]
        \TAIL
          strb    v1, [sp, #\X+2*\W]
           strb    v2, [sp, #\X+3*\W]
        .endm

        @ Macro for rendering a column of 4 pixels to a scratchpad on the stack
        @ (non- power-of-two texture size)
        @
        @ X = column number within scratchpad
        @ W = width of scratchpad
        @ INC = increment for line list pointer
        @ TAIL = optional instruction to insert near end
        @
        .macro COLUMN4N X W INC TAIL
        @ Round-robin loop scheduling is neatest for ARM11, and luckily
        @ we have enough registers
        smlatt  a1, v5, a3, a3 @ Row 0
        add     v5, v5, ip
         smlatt  a2, v5, a3, a3 @ Row 1
         add     v5, v5, ip
        ldrb    a1, [v6, a1, asr #16] @ issue texture loads as soon as possible, as that's most likely to stall
          smlatt   v1, v5, a3, a3 @ Row 2
         ldrb    a2, [v6, a2, asr #16]
          add      v5, v5, ip
           smlatt   v2, v5, a3, a3 @ Row 3
          ldrb     v1, [v6, v1, asr #16]
           add      v5, v5, ip
            str      v5, [v3], #\INC @ Write back new vpos
           ldrb     v2, [v6, v2, asr #16]
        ldrb    a1, [lr, a1]
         ldrb    a2, [lr, a2]
          ldrb     v1, [lr, v1]
           ldrb     v2, [lr, v2]
        strb    a1, [sp, #\X]
         strb    a2, [sp, #\X+\W]
        \TAIL @ exra cycle delay if LDM used here?
          strb     v1, [sp, #\X+2*\W]
           strb     v2, [sp, #\X+3*\W]
        .endm

        @ Macro for rendering a column of four masked pixels straight to screen
        @ (power-of-two texture size)
        @
        @ X = column number (unused, leftover from old version)
        @ W = width (unused, leftover from old version)
        @ INC = increment for line list pointer
        @ TAIL, TAIL1 = optional instructions to insert near end (help avoid
        @               pipeline stalls)
        @
        @ a2 = line list ptr
        @ a3 = screen ptr
        @ a4 = bpl
        @ v1-v4 = current line parameters
        @ v5, v6, lr = temp
        @ ip = logy
        @
        .macro MCOLUMN4 X W INC TAIL TAIL1
        mov     lr, v1, lsr ip @ Row 0
        add     v5, a3, a4, lsl #1
        ldrb    lr, [v2, lr]
        add     v1, v1, v3
         mov     v6, v1, lsr ip @ Row 1
        cmp     lr, #255
        ldrneb  lr, [v4, lr]
         ldrb    v6, [v2, v6]
         add     v1, v1, v3
        strneb  lr, [a3]
         cmp     v6, #255
         ldrneb  v6, [v4, v6]
        mov     lr, v1, lsr ip @ Row 2
        add     v1, v1, v3
         strneb  v6, [a3, a4]
        ldrb    lr, [v2, lr]
         mov     v6, v1, lsr ip @ Row 3
         add     v1, v1, v3
        cmp     lr, #255
        ldrneb  lr, [v4, lr]
         ldrb    v6, [v2, v6]
         \TAIL1
        strneb  lr, [v5]
         cmp     v6, #255
         ldrneb  v6, [v4, v6]
         str     v1, [a2], #\INC
         \TAIL
         strneb  v6, [v5, a4]
         .endm

        @ Macro for rendering a column of four masked pixels straight to screen
        @ (non- power-of-two texture size)
        @
        @ X = column number (unused, leftover from old version)
        @ W = width (unused, leftover from old version)
        @ INC = increment for line list pointer
        @ TAIL, TAIL1 = optional instructions to insert near end (help avoid
        @               pipeline stalls)
        @
        @ a2 = line list ptr
        @ a3 = screen ptr
        @ a4 = bpl
        @ v1-v4 = current line parameters
        @ v5, v6, lr = temp
        @ ip = texture height & magic offset
        @
        .macro MCOLUMN4N X W INC TAIL TAIL1
        smlatt  lr, v1, ip, ip @ Row 0
        add     v1, v1, v3
         smlatt  v6, v1, ip, ip @ Row 1
         add     v1, v1, v3
        ldrb    lr, [v2, lr, asr #16]
          smlatt  v5, v1, ip, ip @ Row 2
         ldrb    v6, [v2, v6, asr #16]
        cmp     lr, #255
        ldrneb  lr, [v4, lr]
          ldrb    v5, [v2, v5, asr #16]
          add     v1, v1, v3
        strneb  lr, [a3]
           smlatt  lr, v1, ip, ip @ Row 3
         cmp     v6, #255
         ldrneb  v6, [v4, v6]
           add     v1, v1, v3
           ldrb    lr, [v2, lr, asr #16]
         strneb  v6, [a3, a4]
          cmp     v5, #255
          ldrneb  v5, [v4, v5]
           add     v6, a3, a4, lsl #1
           str     v1, [a2], #\INC
          strneb  v5, [v6]
           cmp     lr, #255
           ldrneb  lr, [v4, lr]
         \TAIL @ column load
           strneb  lr, [v6, a4]
         \TAIL1 @ a3 correction
         .endm

        @ Macro for rendering a column of four translucent pixels straight to screen
        @ (power-of-two texture size)
        @
        @ X = column number (unused, leftover from old version)
        @ W = width (unused, leftover from old version)
        @ INC = increment for line list pointer
        @ TAIL, TAIL1 = optional instructions to insert near end (help avoid
        @               pipeline stalls)
        @
        @ a2 = line list ptr
        @ a3 = screen ptr
        @ a4 = bpl
        @ v1-v4 = current line parameters
        @ v5 = blend table ptr
        @ a1, v6, lr = temp
        @ ip = logy
        @ C flag = transm (0 = pp:tex indexing, 1 = tex:pp indexing)
        @
        .macro TCOLUMN4 X W INC TAIL TAIL1 TAIL2
        mov     lr, v1, lsr ip @ Row 0
        add     v1, v1, v3
         mov     v6, v1, lsr ip @ Row 1
        ldrb    lr, [v2, lr]
         add     v1, v1, v3
         ldrb    v6, [v2, v6]
        teq     lr, #255
        ldrneb  a1, [a3]
        ldrneb  lr, [v4, lr]
        @
        @
        orrcc   lr, lr, a1, lsl #8
        orrcs   lr, a1, lr, lsl #8
        @
        ldrneb  lr, [v5, lr]
        @
        @
        strneb  lr, [a3]
         teq     v6, #255
         ldrneb  a1, [a3, a4]
         ldrneb  v6, [v4, v6]
          mov     lr, v1, lsr ip @ Row 2
          add     v1, v1, v3
         orrcc   v6, v6, a1, lsl #8
         orrcs   v6, a1, v6, lsl #8
          ldrb    lr, [v2, lr]
         ldrneb  v6, [v5, v6]
         movne   a1, a3
         add     a3, a3, a4, lsl #1
         strneb  v6, [a1, a4]
          teq     lr, #255
          ldrneb  a1, [a3]
          ldrneb  lr, [v4, lr]
           mov     v6, v1, lsr ip @ Row 3
           add     v1, v1, v3
          orrcc   lr, lr, a1, lsl #8
          orrcs   lr, a1, lr, lsl #8
           ldrb    v6, [v2, v6]
          ldrneb  lr, [v5, lr]
        str     v1, [a2], #\INC
          @
          strneb  lr, [a3]
           teq     v6, #255
           ldrneb  a1, [a3, a4]
           ldrneb  v6, [v4, v6]
           movne   lr, a3
        \TAIL1
           orrcc   v6, v6, a1, lsl #8
           orrcs   v6, a1, v6, lsl #8
        \TAIL
           ldrneb  v6, [v5, v6]
        \TAIL2
           @
           strneb  v6, [lr, a4]
        .endm

        @ Macro for rendering a column of four translucent pixels straight to screen
        @ (non- power-of-two texture size)
        @
        @ X = column number (unused, leftover from old version)
        @ W = width (unused, leftover from old version)
        @ INC = increment for line list pointer
        @ TAIL, TAIL1 = optional instructions to insert near end (help avoid
        @               pipeline stalls)
        @
        @ a2 = line list ptr
        @ a3 = screen ptr
        @ a4 = bpl
        @ v1-v4 = current line parameters
        @ v5 = blend table ptr
        @ a1, v6, lr = temp
        @ ip = texture height & magic offset
        @ C flag = transm (0 = pp:tex indexing, 1 = tex:pp indexing)
        @
        .macro TCOLUMN4N X W INC TAIL TAIL1 TAIL2
        smlatt  lr, v1, ip, ip @ Row 0
        add     v1, v1, v3
         smlatt  v6, v1, ip, ip @ Row 1
        @
        ldrb    lr, [v2, lr, asr #16]
         add     v1, v1, v3
         ldrb    v6, [v2, v6, asr #16]
        teq     lr, #255
        ldrneb  a1, [a3]
        ldrneb  lr, [v4, lr]
        @
        @
        orrcc   lr, lr, a1, lsl #8
        orrcs   lr, a1, lr, lsl #8
        @
        ldrneb  lr, [v5, lr]
        @
        @
        strneb  lr, [a3]
         teq     v6, #255
         ldrneb  a1, [a3, a4]
         ldrneb  v6, [v4, v6]
          smlatt  lr, v1, ip, ip @ Row 2
          add     v1, v1, v3
         orrcc   v6, v6, a1, lsl #8
         orrcs   v6, a1, v6, lsl #8
          ldrb    lr, [v2, lr, asr #16]
         ldrneb  v6, [v5, v6]
         movne   a1, a3
         add     a3, a3, a4, lsl #1
         strneb  v6, [a1, a4]
          teq     lr, #255
          ldrneb  a1, [a3]
          ldrneb  lr, [v4, lr]
           smlatt  v6, v1, ip, ip @ Row 3
           add     v1, v1, v3
          orrcc   lr, lr, a1, lsl #8
          orrcs   lr, a1, lr, lsl #8
           ldrb    v6, [v2, v6, asr #16]
          ldrneb  lr, [v5, lr]
        str     v1, [a2], #\INC
          @
          strneb  lr, [a3]
           teq     v6, #255
           ldrneb  a1, [a3, a4]
           ldrneb  v6, [v4, v6]
           movne   lr, a3
        \TAIL1
           orrcc   v6, v6, a1, lsl #8
           orrcs   v6, a1, v6, lsl #8
        \TAIL
           ldrneb  v6, [v5, v6]
        \TAIL2
           @
           strneb  v6, [lr, a4]
        .endm

        @ vblockasm: Render 1, 2, 4, 8 or 16 columns, pow2 texture
        .global vblockasm
        FUNCNAME vblockasm
vblockasm:
        cmp     a3, #2
        bgt     vblockasm_wide
        beq     vblock2x4asm
        stmfd   sp!,{v1-v4,lr}
        ldr     a3, =arm_frameoffset
        ldr     a4, =arm_bpl
        ldr     ip, =arm_glogy
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        ldr     a3, [a3]
        ldr     a4, [a4]
        ldr     ip, [ip]
vblock1_1:
        mov     lr, v1, lsr ip
        ldrb    lr, [v2, lr]
        add     v1, v1, v3
        ldrb    lr, [v4, lr]
        subs    a1, a1, #1
        strb    lr, [a3], a4
        bne     vblock1_1
        str     v1, [a2]
        ldmfd   sp!,{v1-v4,pc}

vblock2x4asm:
        stmfd   sp!,{v1-v6,lr}
      @ Ensure inner loop has doubleword aligned sp
      mov ip, sp
      sub sp, sp, #4
      bic sp, sp, #7
      sub sp, sp, #4
      str ip, [sp]
        sub     sp, sp, #4
        mov     a4, a1 @ height
        mov     v3, a2 @ vlines
        ldr     a1, =arm_bpl
        ldr     a1, [a1]
        stmfd   sp!, {a1,a2}
        ldr     a2, =arm_frameoffset
        ldr     a2, [a2]
        ldr     a3, =arm_glogy
        ldr     a3, [a3]
        str     a4, [sp, #8]
        sub     sp, sp, #8
vblock2x4_l2:
        ldmia   v3, {v5,v6,ip,lr} @ Load first column
        str     a2, [sp, #8+4]    @ stash a2 before it gets clobbered
        subs    a4, a4, #4        @ decrement row count
        @ Build a 2x4 pixel block on the stack
        COLUMN4  0,2,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  1,2,16*-1, "ldrd    a1, [sp, #8]"

        ldrh    v5, [sp]
        ldrh    v6, [sp, #2]
        ldrh    ip, [sp, #4]
        strh    v5, [a2], a1      @ row 0
        ldrh    lr, [sp, #6]
        strh    v6, [a2], a1      @ row 1
        strh    ip, [a2], a1      @ row 2
        strh    lr, [a2], a1      @ row 3

        bgt     vblock2x4_l2

      ldr     sp, [sp, #12+8]
        ldmfd   sp!,{v1-v6,pc}

vblockasm_wide:
        cmp     a3, #8
        bgt     vblock16x4asm
        beq     vblock8x4asm
        stmfd   sp!,{v1-v6,lr}
      @ Ensure inner loop has doubleword aligned sp
      mov ip, sp
      sub sp, sp, #4
      bic sp, sp, #7
      sub sp, sp, #4
      str ip, [sp]
        sub     sp, sp, #4
        mov     a4, a1 @ height
        mov     v3, a2 @ vlines
        ldr     a1, =arm_bpl
        ldr     a1, [a1]
        stmfd   sp!, {a1,a2}
        ldr     a2, =arm_frameoffset
        ldr     a2, [a2]
        ldr     a3, =arm_glogy
        ldr     a3, [a3]
        str     a4, [sp, #8]
        sub     sp, sp, #16
vblock4x4_l2:
        ldmia   v3, {v5,v6,ip,lr} @ Load first column
        str     a2, [sp, #16+4]   @ stash a2 before it gets clobbered
        subs    a4, a4, #4        @ decrement row count
        @ Build a 4x4 pixel block on the stack
        COLUMN4  0,4,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  1,4,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  2,4,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  3,4,16*-3, "ldrd    a1, [sp, #16]"

        ldmia   sp, {v5,v6,ip,lr} @ Grab the 4x4 block
        @
        @
        str     v5, [a2], a1      @ row 0
        str     v6, [a2], a1      @ row 1
        str     ip, [a2], a1      @ row 2
        str     lr, [a2], a1      @ row 3

        bgt     vblock4x4_l2

      ldr     sp, [sp, #12+16]
        ldmfd   sp!,{v1-v6,pc}

vblock8x4asm:
        stmfd   sp!,{v1-v6,lr}
      @ Ensure inner loop has doubleword aligned sp
      mov ip, sp
      sub sp, sp, #4
      bic sp, sp, #7
      sub sp, sp, #4
      str ip, [sp]
        sub     sp, sp, #4
        mov     a4, a1 @ height
        mov     v3, a2 @ vlines
        ldr     a1, =arm_bpl
        ldr     a1, [a1]
        stmfd   sp!, {a1,a2}
        ldr     a2, =arm_frameoffset
        ldr     a2, [a2]
        ldr     a3, =arm_glogy
        ldr     a3, [a3]
        str     a4, [sp, #8]
        sub     sp, sp, #32
vblock8x4_l2:
        ldmia   v3, {v5,v6,ip,lr} @ Load first column
        str     a2, [sp, #32+4]   @ stash a2 before it gets clobbered
        subs    a4, a4, #4        @ decrement row count
        @ Build a 8x4 pixel block on the stack
        COLUMN4  0,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  1,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  2,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  3,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  4,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  5,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  6,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  7,8,16*-7, "ldrd    a1, [sp, #32]"

        ldmia   sp!, {v5,v6,ip,lr}@ grab rows 0+1
        @
        @
        strd    v5, [a2], a1      @ store row 0
        ldrd    v5, [sp], #8      @ grab row 2
        stmia   a2, {ip,lr}       @ store row 1
        add     a2, a2, a1
        ldmia   sp, {ip,lr}       @ grab row 3
        strd    v5, [a2], a1      @ store row 2
        sub     sp, sp, #24
        stmia   a2, {ip,lr}       @ store row 3
        add     a2, a2, a1

        bgt     vblock8x4_l2

      ldr     sp, [sp, #12+32]
        ldmfd   sp!,{v1-v6,pc}

vblock16x4asm:
        stmfd   sp!,{v1-v6,lr}
      @ Ensure inner loop has quadword aligned sp
      mov ip, sp
      sub sp, sp, #4
      bic sp, sp, #15
      sub sp, sp, #4
      str ip, [sp]
        sub     sp, sp, #4
        mov     a4, a1 @ height
        mov     v3, a2 @ vlines
        ldr     a1, =arm_bpl
        ldr     a1, [a1]
        stmfd   sp!, {a1,a2}
        ldr     a2, =arm_frameoffset
        ldr     a2, [a2]
        ldr     a3, =arm_glogy
        ldr     a3, [a3]
        str     a4, [sp, #8]
        sub     sp, sp, #64
vblock16x4_l2:
        ldmia   v3, {v5,v6,ip,lr} @ Load first column
        str     a2, [sp, #64+4]   @ stash a2 before it gets clobbered
        subs    a4, a4, #4        @ decrement row count
        @ Build a 16x4 pixel block on the stack
        COLUMN4  0,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  1,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  2,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  3,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  4,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  5,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  6,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  7,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  8,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4  9,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4 10,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4 11,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4 12,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4 13,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4 14,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4 15,16,16*-15,"ldrd    a1, [sp, #64]"

        ldmia   sp!, {v5,v6,ip,lr}@ grab row 0 (could shift it a couple of instructions earlier, if the macro is able to cope with SP adjustment)
        @
        @
        stmia   a2, {v5,v6,ip,lr} @ store row 0
        ldmia   sp!, {v5,v6,ip,lr}@ grab row 1
        add     a2, a2, a1
        @
        stmia   a2, {v5,v6,ip,lr} @ store row 1
        ldmia   sp!, {v5,v6,ip,lr}@ grab row 2
        add     a2, a2, a1
        @
        stmia   a2, {v5,v6,ip,lr} @ store row 2
        ldmia   sp, {v5,v6,ip,lr} @ grab row 3
        add     a2, a2, a1
        sub     sp, sp, #16*3
        stmia   a2, {v5,v6,ip,lr} @ store row 3
        add     a2, a2, a1

        bgt     vblock16x4_l2

      ldr     sp, [sp, #12+64]
        ldmfd   sp!,{v1-v6,pc}

        .ltorg

        @ vblocknasm: Render 1, 2, 4, 8, or 16 columns, non-pow2 texture
        .global vblocknasm
        FUNCNAME vblocknasm
vblocknasm:
        cmp     a3, #2
        bgt     vblocknasm_wide
        beq     vblocknasm2x4
        stmfd   sp!,{v1-v4,lr}
        ldr     a3, =arm_frameoffset
        ldr     a4, =arm_bpl
        ldr     ip, =arm_tilesize
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        ldr     a3, [a3]
        ldr     a4, [a4]
        ldr     ip, [ip]
vblocknasm1_1:
        smlatt  lr, v1, ip, ip
        ldrb    lr, [v2, lr, asr #16]
        add     v1, v1, v3
        ldrb    lr, [v4, lr]
        subs    a1, a1, #1
        strb    lr, [a3], a4
        bne     vblocknasm1_1
        str     v1, [a2]
        ldmfd   sp!,{v1-v4,pc}

vblocknasm2x4:
        stmfd   sp!,{v1-v6,lr}
      @ Ensure inner loop has doubleword aligned sp
      mov ip, sp
      sub sp, sp, #4
      bic sp, sp, #7
      sub sp, sp, #4
      str ip, [sp]
        sub     sp, sp, #4
        mov     a4, a1 @ height
        mov     v3, a2 @ vlines
        ldr     a1, =arm_bpl
        ldr     a1, [a1]
        stmfd   sp!, {a1,a2}
        ldr     a2, =arm_frameoffset
        ldr     a2, [a2]
        ldr     a3, =arm_tilesize
        ldr     a3, [a3]
        str     a4, [sp, #8]
        sub     sp, sp, #8
vblocknasm2x4_l2:
        ldmia   v3, {v5,v6,ip,lr} @ Load first column
        str     a2, [sp, #8+4]    @ stash a2 before it gets clobbered
        subs    a4, a4, #4        @ decrement row count
        @ Build a 2x4 pixel block on the stack
        COLUMN4N  0,2,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  1,2,16*-1, "ldrd    a1, [sp, #8]"

        ldrh    v5, [sp]
        ldrh    v6, [sp, #2]
        ldrh    ip, [sp, #4]
        strh    v5, [a2], a1      @ row 0
        ldrh    lr, [sp, #6]
        strh    v6, [a2], a1      @ row 1
        strh    ip, [a2], a1      @ row 2
        strh    lr, [a2], a1      @ row 3

        bgt     vblocknasm2x4_l2

      ldr     sp, [sp, #12+8]
        ldmfd   sp!,{v1-v6,pc}

vblocknasm_wide:
        cmp     a3, #8
        bgt     vblocknasm16x4
        beq     vblocknasm8x4
        stmfd   sp!,{v1-v6,lr}
      @ Ensure inner loop has doubleword aligned sp
      mov ip, sp
      sub sp, sp, #4
      bic sp, sp, #7
      sub sp, sp, #4
      str ip, [sp]
        sub     sp, sp, #4
        mov     a4, a1 @ height
        mov     v3, a2 @ vlines
        ldr     a1, =arm_bpl
        ldr     a1, [a1]
        stmfd   sp!, {a1,a2}
        ldr     a2, =arm_frameoffset
        ldr     a2, [a2]
        ldr     a3, =arm_tilesize
        ldr     a3, [a3]
        str     a4, [sp, #8]
        sub     sp, sp, #16
vblocknasm4x4_l2:
        ldmia   v3, {v5,v6,ip,lr} @ Load first column
        str     a2, [sp, #16+4]   @ stash a2 before it gets clobbered
        subs    a4, a4, #4        @ decrement row count
        @ Build a 4x4 pixel block on the stack
        COLUMN4N  0,4,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  1,4,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  2,4,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  3,4,16*-3, "ldrd    a1, [sp, #16]"

        ldmia   sp, {v5,v6,ip,lr} @ Grab the 4x4 block
        str     v5, [a2], a1      @ row 0
        str     v6, [a2], a1      @ row 1
        str     ip, [a2], a1      @ row 2
        str     lr, [a2], a1      @ row 3

        bgt     vblocknasm4x4_l2

      ldr     sp, [sp, #12+16]
        ldmfd   sp!,{v1-v6,pc}

vblocknasm8x4:
        stmfd   sp!,{v1-v6,lr}
      @ Ensure inner loop has doubleword aligned sp
      mov ip, sp
      sub sp, sp, #4
      bic sp, sp, #7
      sub sp, sp, #4
      str ip, [sp]
        sub     sp, sp, #4
        mov     a4, a1 @ height
        mov     v3, a2 @ vlines
        ldr     a1, =arm_bpl
        ldr     a1, [a1]
        stmfd   sp!, {a1,a2}
        ldr     a2, =arm_frameoffset
        ldr     a2, [a2]
        ldr     a3, =arm_tilesize
        ldr     a3, [a3]
        str     a4, [sp, #8]
        sub     sp, sp, #32
vblocknasm8x4_l2:
        ldmia   v3, {v5,v6,ip,lr} @ Load first column
        str     a2, [sp, #32+4]   @ stash a2 before it gets clobbered
        subs    a4, a4, #4        @ decrement row count
        @ Build a 8x4 pixel block on the stack
        COLUMN4N  0,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  1,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  2,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  3,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  4,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  5,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  6,8,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  7,8,16*-7, "ldrd    a1, [sp, #32]"

        ldmia   sp!, {v5,v6,ip,lr}@ grab rows 0+1
        strd    v5, [a2], a1      @ store row 0
        ldrd    v5, [sp], #8      @ grab row 2
        stmia   a2, {ip,lr}       @ store row 1
        add     a2, a2, a1
        ldmia   sp, {ip,lr}       @ grab row 3
        strd    v5, [a2], a1      @ store row 2
        sub     sp, sp, #24
        stmia   a2, {ip,lr}       @ store row 3
        add     a2, a2, a1

        bgt     vblocknasm8x4_l2

      ldr     sp, [sp, #12+32]
        ldmfd   sp!,{v1-v6,pc}

vblocknasm16x4:
        stmfd   sp!,{v1-v6,lr}
      @ Ensure inner loop has quadword aligned sp
      mov ip, sp
      sub sp, sp, #4
      bic sp, sp, #15
      sub sp, sp, #4
      str ip, [sp]
        sub     sp, sp, #4
        mov     a4, a1 @ height
        mov     v3, a2 @ vlines
        ldr     a1, =arm_bpl
        ldr     a1, [a1]
        stmfd   sp!, {a1,a2}
        ldr     a2, =arm_frameoffset
        ldr     a2, [a2]
        ldr     a3, =arm_tilesize
        ldr     a3, [a3]
        str     a4, [sp, #8]
        sub     sp, sp, #64
vblocknasm16x4_l2:
        ldmia   v3, {v5,v6,ip,lr} @ Load first column
        str     a2, [sp, #64+4]   @ stash a2 before it gets clobbered
        subs    a4, a4, #4        @ decrement row count
        @ Build a 16x4 pixel block on the stack
        COLUMN4N  0,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  1,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  2,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  3,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  4,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  5,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  6,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  7,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  8,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N  9,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N 10,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N 11,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N 12,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N 13,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N 14,16,16,    "ldmia   v3, {v5,v6,ip,lr}"
        COLUMN4N 15,16,16*-15,"ldrd    a1, [sp, #64]"

        ldmia   sp!, {v5,v6,ip,lr}@ grab row 0
        stmia   a2, {v5,v6,ip,lr} @ store row 0
        ldmia   sp!, {v5,v6,ip,lr}@ grab row 1
        add     a2, a2, a1
        stmia   a2, {v5,v6,ip,lr} @ store row 1
        ldmia   sp!, {v5,v6,ip,lr}@ grab row 2
        add     a2, a2, a1
        stmia   a2, {v5,v6,ip,lr} @ store row 2
        ldmia   sp, {v5,v6,ip,lr} @ grab row 3
        add     a2, a2, a1
        sub     sp, sp, #16*3
        stmia   a2, {v5,v6,ip,lr} @ store row 3
        add     a2, a2, a1

        bgt     vblocknasm16x4_l2

      ldr     sp, [sp, #12+64]
        ldmfd   sp!,{v1-v6,pc}

        .ltorg

        @ mvblockasm: Render 1, 2, 4, 8 or 16 columns, pow2 masked texture
        FUNCNAME mvblockasm
        .global mvblockasm
mvblockasm:
        cmp     a3, #2
        bgt     mvblockasm_wide
        beq     mvblock2x4asm
        movs    a1, a1, lsr #1
        ldr     ip, =arm_glogy
        bne     mvblock1asm_lots
        @ Tuned for 1 pixel
        stmfd   sp!, {v1,lr}
        ldr     ip, [ip]
        ldmia   a2, {a3,a4,v1,lr}
        ldr     a1, =arm_frameoffset
        @ probably 1 cycle here
        mov     ip, a3, lsr ip
        add     a3, a3, v1
        ldrb    ip, [a4, ip]
        ldr     a1, [a1]
        str     a3, [a2]
        teq     ip, #255
        ldrneb  ip, [lr, ip]
        ldmeqfd sp!, {v1,pc} @ early-ish exit for translucent
        ldmfd   sp!, {v1,lr}
        strb    ip, [a1]
        mov     pc, lr

mvblock1asm_lots:
        @ Tuned for 2+ pixels
        stmfd   sp!, {v1-v6,lr}
        ldr     a3, =arm_frameoffset
        ldr     ip, [ip]
        ldr     a4, =arm_bpl
        ldmia   a2, {v1-v4}
        ldr     a3, [a3]
        ldr     a4, [a4]
        mov     lr, v1, lsr ip
        add     v1, v1, v3
        ldrb    lr, [v2, lr]
        bcc     mvblock1asm_even
        @ Odd count, do the initial pixel
        @
        teq     lr, #255
        ldrneb  lr, [v4, lr]
        mov     v5, a3       @ fill some space
        add     a3, a3, a4
        strneb  lr, [v5]

        mov     lr, v1, lsr ip @ row 0
mvblock1asm_l2:
        add     v1, v1, v3
        ldrb    lr, [v2, lr]
mvblock1asm_even:
         mov     v5, v1, lsr ip @ row 1
         add     v1, v1, v3
        teq     lr, #255
        ldrneb  lr, [v4, lr]
         ldrb    v5, [v2, v5]
         add     v6, a3, a4
        strneb  lr, [a3]
         teq     v5, #255
         ldrneb  v5, [v4, v5]
        add     a3, a3, a4, lsl #1
          mov     lr, v1, lsr ip @ row 2
         strneb  v5, [v6]
        subs    a1, a1, #1
        bne     mvblock1asm_l2
        str     v1, [a2]
        ldmfd   sp!,{v1-v6,pc}

mvblock2x4asm:
        ldr     a4, =arm_bpl
        ldr     ip, =arm_glogy
        ldr     a3, =arm_frameoffset
        ldr     a4, [a4]
        ldr     ip, [ip]
        stmfd   sp!,{v1-v6,lr}
        ldr     a3, [a3]
mvblock2x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        MCOLUMN4 0,2,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 1,2,-16,"add a3,a3,a4,lsl #2","sub a3,a3,#1"
        subs    a1, a1, #4
        bne     mvblock2x4asm_l1
        ldmia   sp!, {v1-v6,pc}

mvblockasm_wide:
        ldr     a4, =arm_bpl
        ldr     ip, =arm_glogy
        cmp     a3, #8
        ldr     a4, [a4]
        ldr     ip, [ip]
        ldr     a3, =arm_frameoffset
        stmfd   sp!,{v1-v6,lr}
        bgt     mvblock16x4asm
        beq     mvblock8x4asm
        ldr     a3, [a3]
mvblock4x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        MCOLUMN4 0,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 1,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 2,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 3,4,-16*3,"add a3,a3,a4,lsl #2","sub a3,a3,#3"
        subs    a1, a1, #4
        bne     mvblock4x4asm_l1
        ldmia   sp!, {v1-v6,pc}

mvblock8x4asm:
        ldr     a3, [a3]
mvblock8x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        MCOLUMN4 0,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 1,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 2,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 3,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 4,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 5,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 6,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 7,8,-16*7,"add a3,a3,a4,lsl #2","sub a3,a3,#7"
        subs    a1, a1, #4
        bne     mvblock8x4asm_l1
        ldmia   sp!, {v1-v6,pc}

mvblock16x4asm:
        ldr     a3, [a3]
mvblock16x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        MCOLUMN4  0,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  1,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  2,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  3,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  4,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  5,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  6,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  7,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  8,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4  9,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 10,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 11,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 12,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 13,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 14,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4 15,16,-16*15,"add a3,a3,a4,lsl #2","sub a3,a3,#15"
        subs    a1, a1, #4
        bne     mvblock16x4asm_l1
        ldmia   sp!, {v1-v6,pc}

        .ltorg

        @ mvblocknasm: Render 1, 2, 4, 8 or 16 columns, non-pow2 masked texture
        FUNCNAME mvblocknasm
        .global mvblocknasm
mvblocknasm:
        cmp     a3, #2
        bgt     mvblocknasm_wide
        beq     mvblockn2x4asm
        movs    a1, a1, lsr #1
        ldr     ip, =arm_tilesize
        bne     mvblockn1asm_lots
        @ Tuned for 1 pixel
        stmfd   sp!, {v1,lr}
        ldr     ip, [ip]
        ldmia   a2, {a3,a4,v1,lr}
        ldr     a1, =arm_frameoffset
        @ probably 1 cycle here
        smlatt  ip, a3, ip, ip
        add     a3, a3, v1
        @
        @
        ldrb    ip, [a4, ip, asr #16]
        ldr     a1, [a1]
        str     a3, [a2]
        teq     ip, #255
        ldrneb  ip, [lr, ip]
        ldmeqfd sp!, {v1,pc} @ early-ish exit for translucent
        ldmfd   sp!, {v1,lr}
        strb    ip, [a1]
        mov     pc, lr

mvblockn1asm_lots:
        @ Tuned for 2+ pixels
        stmfd   sp!, {v1-v6,lr}
        ldr     a3, =arm_frameoffset
        ldr     ip, [ip]
        ldr     a4, =arm_bpl
        ldmia   a2, {v1-v4}
        ldr     a3, [a3]
        ldr     a4, [a4]
        smlatt  lr, v1, ip, ip
        add     v1, v1, v3
        ldrb    lr, [v2, lr, asr #16]
        bcc     mvblockn1asm_even
        @ Odd count, do the initial pixel
        @
        teq     lr, #255
        ldrneb  lr, [v4, lr]
        mov     v5, a3       @ fill some space
        add     a3, a3, a4
        strneb  lr, [v5]

        smlatt  lr, v1, ip, ip @ row 0
mvblockn1asm_l2:
        add     v1, v1, v3
        ldrb    lr, [v2, lr, asr #16]
mvblockn1asm_even:
         smlatt  v5, v1, ip, ip @ row 1
         add     v1, v1, v3
        teq     lr, #255
        ldrneb  lr, [v4, lr]
         ldrb    v5, [v2, v5, asr #16]
         add     v6, a3, a4
        strneb  lr, [a3]
         teq     v5, #255
         ldrneb  v5, [v4, v5]
        add     a3, a3, a4, lsl #1
          smlatt  lr, v1, ip, ip @ row 2
         strneb  v5, [v6]
        subs    a1, a1, #1
        bne     mvblockn1asm_l2
        str     v1, [a2]
        ldmfd   sp!,{v1-v6,pc}

mvblockn2x4asm:
        ldr     a4, =arm_bpl
        ldr     ip, =arm_tilesize
        ldr     a3, =arm_frameoffset
        ldr     a4, [a4]
        ldr     ip, [ip]
        stmfd   sp!,{v1-v6,lr}
        ldr     a3, [a3]
mvblockn2x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        MCOLUMN4N 0,2,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 1,2,-16,"add a3,a3,a4,lsl #2","sub a3,a3,#1"
        subs    a1, a1, #4
        bne     mvblockn2x4asm_l1
        ldmia   sp!, {v1-v6,pc}

mvblocknasm_wide:
        ldr     a4, =arm_bpl
        ldr     ip, =arm_tilesize
        cmp     a3, #8
        ldr     a4, [a4]
        ldr     ip, [ip]
        ldr     a3, =arm_frameoffset
        stmfd   sp!,{v1-v6,lr}
        bgt     mvblockn16x4asm
        beq     mvblockn8x4asm
        ldr     a3, [a3]
mvblockn4x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        MCOLUMN4N 0,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 1,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 2,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 3,4,-16*3,"add a3,a3,a4,lsl #2","sub a3,a3,#3"
        subs    a1, a1, #4
        bne     mvblockn4x4asm_l1
        ldmia   sp!, {v1-v6,pc}

mvblockn8x4asm:
        ldr     a3, [a3]
mvblockn8x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        MCOLUMN4N 0,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 1,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 2,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 3,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 4,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 5,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 6,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 7,8,-16*7,"add a3,a3,a4,lsl #2","sub a3,a3,#7"
        subs    a1, a1, #4
        bne     mvblockn8x4asm_l1
        ldmia   sp!, {v1-v6,pc}

mvblockn16x4asm:
        ldr     a3, [a3]
mvblockn16x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        MCOLUMN4N  0,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  1,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  2,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  3,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  4,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  5,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  6,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  7,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  8,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N  9,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 10,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 11,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 12,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 13,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 14,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1"
        MCOLUMN4N 15,16,-16*15,"add a3,a3,a4,lsl #2","sub a3,a3,#15"
        subs    a1, a1, #4
        bne     mvblockn16x4asm_l1
        ldmia   sp!, {v1-v6,pc}

        .ltorg

        @ tvblockasm: Render 1, 2, 4, 8 or 16 columns, pow2 translucent texture
        FUNCNAME tvblockasm
        .global tvblockasm
tvblockasm:
        cmp     a3, #2
        bgt     tvblockasm_wide
        beq     tvblock2x4asm
        movs    a1, a1, lsr #1
        ldr     ip, =arm_glogy
        bne     tvblock1asm_lots
        @ Tuned for 1 pixel
        stmfd   sp!, {v1,v2,lr}
        ldr     ip, [ip]
        ldmia   a2, {a3,a4,v1,lr}
        ldr     a1, =arm_frameoffset
        mov     ip, a3, lsr ip
        add     a3, a3, v1
        ldr     v1, =arm_transmode
        ldrb    ip, [a4, ip]
        ldr     a1, [a1]
        str     a3, [a2]
        teq     ip, #255
        ldrne   a2, =arm_gtrans
        ldrne   v1, [v1]
        ldmeqfd sp!, {v1,v2,pc} @ early-ish exit for translucent
        ldrb    ip, [lr, ip]
        ldrb    lr, [a1]
        ldr     a2, [a2]
        cmp     v1, #0
        orreq   ip, ip, lr, lsl #8
        orrne   ip, lr, ip, lsl #8
        ldrb    ip, [a2, ip]
        ldmia   sp!, {v1,v2,lr}
        strb    ip, [a1]
        mov     pc, lr

tvblock1asm_lots:
        @ Tuned for 2+ pixels
        stmfd   sp!, {v1-v6,lr}
        ldr     a3, =arm_frameoffset
        ldr     ip, [ip]
        ldr     a4, =arm_bpl
        ldr     v6, =arm_transmode
        ldr     v5, =arm_gtrans
        ldmia   a2, {v1-v4}
        ldr     a3, [a3]
        ldr     a4, [a4]
        ldr     v6, [v6]
        ldr     v5, [v5]
        mov     lr, v1, lsr ip
        orr     ip, ip, v6, lsl #8 @ pack transm flag into logy (register-specified shifts only use the low 8 bits of the register)
        add     v1, v1, v3
        ldrb    lr, [v2, lr]
        str     a2, [sp, #-4]!
        bcc     tvblock1asm_even
        @ Odd count, do the initial pixel
        cmp     ip, #256 @ load transm into carry flag
        teq     lr, #255
        ldrneb  a2, [a3]
        ldrneb  lr, [v4, lr]
        movne   v6, a3
        orrcc   lr, lr, a2, lsl #8
        orrcs   lr, a2, lr, lsl #8
        ldrneb  lr, [v5, lr]
        mov     a2, v1, lsr ip @ row 0
        add     a3, a3, a4
        strneb  lr, [v6]

        ldrb    lr, [v2, a2]
tvblock1asm_l2:
        add     v1, v1, v3
tvblock1asm_even:
        cmp     ip, #256 @ load transm into carry flag
         mov     v6, v1, lsr ip @ Row 1
         add     v1, v1, v3
        teq     lr, #255
        ldrneb  a2, [a3]
        ldrneb  lr, [v4, lr]
         ldrb    v6, [v2, v6]
        @
        orrcc   lr, lr, a2, lsl #8
        orrcs   lr, a2, lr, lsl #8
        @
        ldrneb  lr, [v5, lr]
        @
        @
        strneb  lr, [a3]
         teq     v6, #255
         ldrneb  a2, [a3, a4]
         ldrneb  v6, [v4, v6]
         add     a3, a3, a4
          mov     lr, v1, lsr ip @ row 2
         orrcc   v6, v6, a2, lsl #8
         orrcs   v6, a2, v6, lsl #8
          ldrb    lr, [v2, lr]
         ldrneb  v6, [v5, v6]
         movne   a2, a3
         add     a3, a3, a4
         strneb  v6, [a2]

        subs    a1, a1, #1

        bne     tvblock1asm_l2
        ldr     a2, [sp], #4
        str     v1, [a2]
        ldmfd   sp!,{v1-v6,pc}

tvblock2x4asm:
        ldr     a4, =arm_bpl
        ldr     ip, =arm_glogy
        ldr     a3, =arm_frameoffset
        ldr     a4, [a4]
        ldr     ip, [ip]
        stmfd   sp!,{v1-v6,lr}
        ldr     v6, =arm_transmode
        ldr     v5, =arm_gtrans
        ldr     a3, [a3]
        sub     sp, sp, #4
        ldr     v6, [v6]
        ldr     v5, [v5]
        orr     ip, ip, v6, lsl #8 @ pack transm flag into logy (register-specified shifts only use the low 8 bits of the register)
tvblock2x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        str     a1, [sp]
        cmp     ip, #256 @ load transm into carry flag
        TCOLUMN4 0,2,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 1,2,-16,"ldr a1,[sp]","add a3,a3,a4,lsl #1","sub a3,a3,#1"
        subs    a1, a1, #4
        bne     tvblock2x4asm_l1
        add     sp, sp, #4
        ldmia   sp!, {v1-v6,pc}

tvblockasm_wide:
        ldr     a4, =arm_bpl
        ldr     ip, =arm_glogy
        cmp     a3, #8
        ldr     a4, [a4]
        ldr     ip, [ip]
        ldr     a3, =arm_frameoffset
        stmfd   sp!,{v1-v6,lr}
        ldr     v6, =arm_transmode
        ldr     v5, =arm_gtrans
        ldr     a3, [a3]
        sub     sp, sp, #4
        ldr     v6, [v6]
        ldr     v5, [v5]
        orr     ip, ip, v6, lsl #8 @ pack transm flag into logy (register-specified shifts only use the low 8 bits of the register)
        bgt     tvblock16x4asm
        beq     tvblock8x4asm
tvblock4x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        str     a1, [sp]
        cmp     ip, #256 @ load transm into carry flag
        TCOLUMN4 0,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 1,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 2,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 3,4,-16*3,"ldr a1,[sp]","add a3,a3,a4,lsl #1","sub a3,a3,#3"
        subs    a1, a1, #4
        bne     tvblock4x4asm_l1
        add     sp, sp, #4
        ldmia   sp!, {v1-v6,pc}

tvblock8x4asm:
tvblock8x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        str     a1, [sp]
        cmp     ip, #256 @ load transm into carry flag
        TCOLUMN4 0,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 1,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 2,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 3,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 4,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 5,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 6,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 7,8,-16*7,"ldr a1,[sp]","add a3,a3,a4,lsl #1","sub a3,a3,#7"
        subs    a1, a1, #4
        bne     tvblock8x4asm_l1
        add     sp, sp, #4
        ldmia   sp!, {v1-v6,pc}

        .ltorg

tvblock16x4asm:
tvblock16x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        str     a1, [sp]
        cmp     ip, #256 @ load transm into carry flag
        TCOLUMN4  0,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  1,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  2,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  3,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  4,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  5,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  6,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  7,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  8,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4  9,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 10,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 11,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 12,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 13,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 14,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4 15,16,-16*15,"ldr a1,[sp]","add a3,a3,a4,lsl #1","sub a3,a3,#15"
        subs    a1, a1, #4
        bne     tvblock16x4asm_l1
        add     sp, sp, #4
        ldmia   sp!, {v1-v6,pc}

        .ltorg

        @ tvblocknasm: Render 1, 2, 4, 8 or 16 columns, non-pow2 translucent texture
        FUNCNAME tvblocknasm
        .global tvblocknasm
tvblocknasm:
        cmp     a3, #2
        bgt     tvblocknasm_wide
        beq     tvblockn2x4asm
        movs    a1, a1, lsr #1
        ldr     ip, =arm_tilesize
        bne     tvblockn1asm_lots
        @ Tuned for 1 pixel
        stmfd   sp!, {v1,v2,lr}
        ldr     ip, [ip]
        ldmia   a2, {a3,a4,v1,lr}
        ldr     a1, =arm_frameoffset
        smlatt  ip, a3, ip, ip
        add     a3, a3, v1
        ldr     v1, =arm_transmode
        str     a3, [a2]
        ldrb    ip, [a4, ip, asr #16]
        ldr     a1, [a1]
        ldr     v1, [v1]
        teq     ip, #255
        ldrne   a2, =arm_gtrans
        ldmeqfd sp!, {v1,v2,pc} @ early-ish exit for translucent
        ldrb    ip, [lr, ip]
        ldrb    lr, [a1]
        ldr     a2, [a2]
        cmp     v1, #0
        orreq   ip, ip, lr, lsl #8
        orrne   ip, lr, ip, lsl #8
        ldrb    ip, [a2, ip]
        ldmia   sp!, {v1,v2,lr}
        strb    ip, [a1]
        mov     pc, lr

tvblockn1asm_lots:
        @ Tuned for 2+ pixels
        stmfd   sp!, {v1-v6,lr}
        ldr     a3, =arm_frameoffset
        ldr     ip, [ip]
        ldr     a4, =arm_bpl
        ldr     v6, =arm_transmode
        ldr     v5, =arm_gtrans
        ldmia   a2, {v1-v4}
        ldr     a3, [a3]
        ldr     v6, [v6]
        ldr     a4, [a4]
        ldr     v5, [v5]
        smlatt  lr, v1, ip, ip
        mov     v6, v6, lsl #31 @ shift transm into high bit
        add     v1, v1, v3
        str     a2, [sp, #-4]!
        ldrb    lr, [v2, lr, asr #16]
        bcc     tvblockn1asm_even
        @ Odd count, do the initial pixel
        cmp     v6, #1<<31 @ load transm into carry flag
        teq     lr, #255
        ldrneb  a2, [a3]
        ldrneb  lr, [v4, lr]
        movne   v6, a3
        orrcc   lr, lr, a2, lsl #8
        orrcs   lr, a2, lr, lsl #8
        ldrneb  lr, [v5, lr]
        smlatt  a2, v1, ip, ip @ row 0
        add     a3, a3, a4
        strneb  lr, [v6]

        mov     v6, v6, rrx @ v6 was corrupted, so recover transm flag from PSR
        ldrb    lr, [v2, a2, asr #16]
tvblockn1asm_l2:
        add     v1, v1, v3
tvblockn1asm_even:
        cmp     v6, #1<<31 @ load transm back into carry flag
         smlatt  v6, v1, ip, ip @ Row 1
         add     v1, v1, v3
        teq     lr, #255
        ldrneb  a2, [a3]
        ldrneb  lr, [v4, lr]
         ldrb    v6, [v2, v6, asr #16]
        @
        orrcc   lr, lr, a2, lsl #8
        orrcs   lr, a2, lr, lsl #8
        @
        ldrneb  lr, [v5, lr]
        @
        @
        strneb  lr, [a3]
         teq     v6, #255
         ldrneb  a2, [a3, a4]
         ldrneb  v6, [v4, v6]
         add     a3, a3, a4
          smlatt  lr, v1, ip, ip @ row 2
         orrcc   v6, v6, a2, lsl #8
         orrcs   v6, a2, v6, lsl #8
          ldrb    lr, [v2, lr, asr #16]
         ldrneb  v6, [v5, v6]
         movne   a2, a3
         add     a3, a3, a4
         strneb  v6, [a2]
        mov     v6, v6, rrx @ get transm back into v6
        subs    a1, a1, #1

        bne     tvblockn1asm_l2
        ldr     a2, [sp], #4
        str     v1, [a2]
        ldmfd   sp!,{v1-v6,pc}

tvblockn2x4asm:
        ldr     a4, =arm_bpl
        ldr     ip, =arm_tilesize
        ldr     a3, =arm_frameoffset
        ldr     a4, [a4]
        ldr     ip, [ip]
        stmfd   sp!,{v1-v6,lr}
        ldr     v6, =arm_transmode
        ldr     v5, =arm_gtrans
        ldr     a3, [a3]
        sub     sp, sp, #4
        ldr     v6, [v6]
        ldr     v5, [v5]
        mov     v6, v6, lsl #31 @ shift transm into high bit
tvblockn2x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        str     a1, [sp]
        cmp     v6, #1<<31 @ load transm into carry flag
        TCOLUMN4N 0,2,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 1,2,-16,"ldr a1,[sp]","add a3,a3,a4,lsl #1","sub a3,a3,#1"
        mov     v6, v6, rrx @ shift transm back into v6
        subs    a1, a1, #4
        bne     tvblockn2x4asm_l1
        add     sp, sp, #4
        ldmia   sp!, {v1-v6,pc}

tvblocknasm_wide:
        ldr     a4, =arm_bpl
        ldr     ip, =arm_tilesize
        cmp     a3, #8
        ldr     a4, [a4]
        ldr     ip, [ip]
        ldr     a3, =arm_frameoffset
        stmfd   sp!,{v1-v6,lr}
        ldr     v6, =arm_transmode
        ldr     v5, =arm_gtrans
        ldr     a3, [a3]
        sub     sp, sp, #4
        ldr     v6, [v6]
        ldr     v5, [v5]
        mov     v6, v6, lsl #31 @ shift transm into high bit
        bgt     tvblockn16x4asm
        beq     tvblockn8x4asm
tvblockn4x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        str     a1, [sp]
        cmp     v6, #1<<31 @ load transm into carry flag
        TCOLUMN4N 0,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 1,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 2,4,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 3,4,-16*3,"ldr a1,[sp]","add a3,a3,a4,lsl #1","sub a3,a3,#3"
        mov     v6, v6, rrx @ shift transm back into v6
        subs    a1, a1, #4
        bne     tvblockn4x4asm_l1
        add     sp, sp, #4
        ldmia   sp!, {v1-v6,pc}

tvblockn8x4asm:
tvblockn8x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        str     a1, [sp]
        cmp     v6, #1<<31 @ load transm into carry flag
        TCOLUMN4N 0,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 1,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 2,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 3,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 4,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 5,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 6,8,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 7,8,-16*7,"ldr a1,[sp]","add a3,a3,a4,lsl #1","sub a3,a3,#7"
        mov     v6, v6, rrx @ shift transm back into v6
        subs    a1, a1, #4
        bne     tvblockn8x4asm_l1
        add     sp, sp, #4
        ldmia   sp!, {v1-v6,pc}

        .ltorg

tvblockn16x4asm:
tvblockn16x4asm_l1:
        ldmia   a2, {v1-v4} @ vpos, buf, vinc, pal
        str     a1, [sp]
        cmp     v6, #1<<31 @ load transm into carry flag
        TCOLUMN4N  0,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  1,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  2,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  3,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  4,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  5,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  6,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  7,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  8,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N  9,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 10,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 11,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 12,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 13,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 14,16,16,"ldmia a2, {v1-v4}","add a3,a3,#1","sub a3,a3,a4,lsl #1"
        TCOLUMN4N 15,16,-16*15,"ldr a1,[sp]","add a3,a3,a4,lsl #1","sub a3,a3,#15"
        mov     v6, v6, rrx @ shift transm back into v6
        subs    a1, a1, #4
        bne     tvblockn16x4asm_l1
        add     sp, sp, #4
        ldmia   sp!, {v1-v6,pc}

        .end
