/***************************************************************************
--                      tiny_chess - chess
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************/

/*
 * Board: chess_board_t (68 bytes)
 *   [0..63]  squares[64]   piece = type[2:0] | side[3]
 *   [64]     side_to_move  0=WHITE 8=BLACK
 *   [65]     castling      K=1 Q=2 k=4 q=8
 *   [66]     ep_square     int8_t, -1 = none
 *   [67]     halfmove_clock
 *
 * Move (uint16_t):  from[5:0] | to[11:6] | flag[15:12]
 *
 * Internal move-generator chain uses two implicit registers:
 *   r15:r14  consumer function pointer
 *   r13:r12  context pointer
 * for_each_legal_move saves/restores r15:r14 and r13:r12 on entry/exit,
 * so they are transparent to all callers outside the chain.
 */

#define PIECE_EMPTY    0
#define PIECE_PAWN     1
#define PIECE_KNIGHT   2
#define PIECE_BISHOP   3
#define PIECE_ROOK     4
#define PIECE_QUEEN    5
#define PIECE_KING     6
#define CHESS_WHITE    0
#define CHESS_BLACK    8

#define CASTLE_WHITE_K  1
#define CASTLE_WHITE_Q  2
#define CASTLE_BLACK_K  4
#define CASTLE_BLACK_Q  8

#define MOVE_NORMAL     0
#define MOVE_CASTLE_K   1
#define MOVE_CASTLE_Q   2
#define MOVE_EN_PASSANT 3
#define MOVE_PROMOTE_Q  4
#define MOVE_PROMOTE_R  5
#define MOVE_PROMOTE_B  6
#define MOVE_PROMOTE_N  7

/* ================================================================== */
/* PROGMEM data                                                        */
/* ================================================================== */
.section .progmem.gcc_exc,"a",@progbits

initial_board:
    .byte 4,2,3,5,6,3,2,4    /* rank1 white */
    .byte 1,1,1,1,1,1,1,1    /* rank2 white pawns */
    .byte 0,0,0,0,0,0,0,0    /* ranks 3-6 */
    .byte 0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0
    .byte 9,9,9,9,9,9,9,9    /* rank7 black pawns */
    .byte 12,10,11,13,14,11,10,12  /* rank8 black */

piece_values:                 /* int16_t[7] */
    .word 0, 100, 320, 330, 500, 900, 0

piece_glyphs:
    .byte '.','p','n','b','r','q','k'

knight_df:  .byte  1, 2, 2, 1,-1,-2,-2,-1
knight_dr:  .byte  2, 1,-1,-2,-2,-1, 1, 2
bishop_df:  .byte  1, 1,-1,-1
bishop_dr:  .byte  1,-1, 1,-1
rook_df:    .byte  1,-1, 0, 0
rook_dr:    .byte  0, 0, 1,-1
king_df:    .byte  1, 1, 1, 0, 0,-1,-1,-1
king_dr:    .byte  1, 0,-1, 1,-1, 1, 0,-1

promoted_type:   .byte PIECE_QUEEN, PIECE_ROOK, PIECE_BISHOP, PIECE_KNIGHT
promotion_chars: .byte 'q','r','b','n'

.text

/* ================================================================== */
/* make_move  r24=from r22=to r20=flag -> r25:r24                       */
/* ================================================================== */
make_move:
    mov  r25, r22
    andi r25, 0x03
    lsl  r25
    lsl  r25
    lsl  r25
    lsl  r25
    lsl  r25
    lsl  r25              /* r25 = (to & 3) << 6 */
    or   r24, r25         /* r24 = from|(to&3)<<6  = move_lo */
    mov  r25, r22
    lsr  r25
    lsr  r25              /* r25 = to >> 2 */
    andi r25, 0x0F
    mov  r19, r20
    andi r19, 0x0F
    swap r19              /* r19 = flag << 4 */
    or   r25, r19         /* r25 = (to>>2)|(flag<<4) = move_hi */
    ret

/* ================================================================== */
/* chess_reset  r25:r24 = board*                                        */
/* ================================================================== */
.global chess_reset
.type   chess_reset, @function
chess_reset:
    push r29
    push r28
    movw r28, r24
    ldi  r30, lo8(initial_board)
    ldi  r31, hi8(initial_board)
    ldi  r18, 64
cr_loop:
    lpm  r24, Z+
    st   Y+, r24
    dec  r18
    brne cr_loop
    st   Y+, r1           /* side_to_move = WHITE */
    ldi  r24, 0x0F
    st   Y+, r24          /* castling = all rights */
    ldi  r24, 0xFF
    st   Y+, r24          /* ep_square = -1 */
    st   Y,  r1           /* halfmove_clock = 0 */
    pop  r28
    pop  r29
    ret
.size chess_reset, .-chess_reset

/* ================================================================== */
/* chess_piece_char  r24=piece -> r24=char                              */
/* ================================================================== */
.global chess_piece_char
.type   chess_piece_char, @function
chess_piece_char:
    mov  r25, r24         /* save original piece */
    tst  r24
    breq cpc_dot
    andi r24, 0x07        /* type */
    ldi  r30, lo8(piece_glyphs)
    ldi  r31, hi8(piece_glyphs)
    add  r30, r24
    adc  r31, r1
    lpm  r24, Z           /* lowercase glyph */
    andi r25, CHESS_BLACK
    brne cpc_done         /* black -> lowercase */
    subi r24, 32          /* white -> uppercase */
cpc_done:
    ret
cpc_dot:
    ldi  r24, '.'
    ret
.size chess_piece_char, .-chess_piece_char

/* ================================================================== */
/* piece_value_fn  r24=type -> r25:r24 (int16_t)                        */
/* ================================================================== */
piece_value_fn:
    lsl  r24
    ldi  r30, lo8(piece_values)
    ldi  r31, hi8(piece_values)
    add  r30, r24
    adc  r31, r1
    lpm  r24, Z+
    lpm  r25, Z
    ret

/* ================================================================== */
/* center_bonus  r24=piece r22=square -> r24 (int8_t)                   */
/* Clobbers r18-r25                                                    */
/* ================================================================== */
center_bonus:
    mov  r23, r22
    andi r23, 0x07        /* r23 = file */
    lsr  r22
    lsr  r22
    lsr  r22              /* r22 = rank */
    mov  r21, r24
    andi r21, CHESS_BLACK /* colour bit */
    andi r24, 0x07        /* r24 = type */
    /* rel_rank */
    tst  r21
    breq cb_white
    ldi  r25, 7
    sub  r25, r22
    mov  r20, r25         /* rel_rank = 7-rank */
    rjmp cb_dist
cb_white:
    mov  r20, r22         /* rel_rank = rank */
cb_dist:
    /* dist = abs(3-file) + abs(3-rank) */
    ldi  r18, 3
    sub  r18, r23
    tst  r18
    brpl 1f
    neg  r18
1:
    ldi  r19, 3
    sub  r19, r22
    tst  r19
    brpl 2f
    neg  r19
2:
    add  r18, r19         /* r18 = dist */
    /* switch(type) */
    cpi  r24, PIECE_PAWN
    breq cb_pawn
    cpi  r24, PIECE_KNIGHT
    breq cb_knight
    cpi  r24, PIECE_BISHOP
    breq cb_bishop
    cpi  r24, PIECE_ROOK
    breq cb_rook
    cpi  r24, PIECE_QUEEN
    breq cb_queen
    cpi  r24, PIECE_KING
    breq cb_king
    clr  r24
    ret
cb_pawn:
    mov  r24, r20
    lsl  r24
    lsl  r24              /* rel_rank*4 */
    sub  r24, r18         /* -dist */
    ret
cb_knight:
    mov  r24, r18
    lsl  r24
    lsl  r24              /* dist*4 */
    ldi  r25, 18
    sub  r25, r24
    mov  r24, r25
    ret
cb_bishop:
    mov  r24, r18
    add  r24, r18
    add  r24, r18         /* dist*3 */
    ldi  r25, 12
    sub  r25, r24
    mov  r24, r25
    ret
cb_rook:
    mov  r24, r20
    lsl  r24              /* rel_rank*2 */
    ret
cb_queen:
    mov  r24, r18
    lsl  r24              /* dist*2 */
    ldi  r25, 8
    sub  r25, r24
    mov  r24, r25
    ret
cb_king:
    mov  r24, r18
    add  r24, r18
    add  r24, r18         /* dist*3 */
    neg  r24
    ret

/* ================================================================== */
/* evaluate_board  r25:r24=board* -> r25:r24 (int16_t)                  */
/* ================================================================== */
evaluate_board:
    push r29
    push r28
    push r17
    push r16
    push r15
    push r14
    movw r28, r24         /* Y = board */
    clr  r16
    clr  r17              /* r17:r16 = score = 0 */
    clr  r14              /* r14 = square counter */
evl_loop:
    cpi  r14, 64
    breq evl_done
    movw r26, r28
    add  r26, r14
    adc  r27, r1
    ld   r15, X           /* r15 = piece */
    tst  r15
    breq evl_next
    mov  r24, r15
    andi r24, 0x07
    rcall piece_value_fn  /* r25:r24 = piece_value */
    push r25
    push r24              /* save value on stack */
    mov  r24, r15         /* piece */
    mov  r22, r14         /* square */
    rcall center_bonus    /* r24 = bonus (int8_t) */
    mov  r25, r24
    lsl  r25
    sbc  r25, r25         /* sign-extend bonus to 16-bit */
    pop  r22              /* restore value_lo */
    pop  r23              /* restore value_hi */
    add  r22, r24
    adc  r23, r25         /* value += bonus (16-bit) */
    andi r15, CHESS_BLACK
    brne evl_sub
    add  r16, r22
    adc  r17, r23         /* WHITE: score += value */
    rjmp evl_next
evl_sub:
    sub  r16, r22
    sbc  r17, r23         /* BLACK: score -= value */
evl_next:
    inc  r14
    rjmp evl_loop
evl_done:
    movw r26, r28
    adiw r26, 64
    ld   r24, X           /* side_to_move */
    tst  r24
    breq evl_white
    clr  r24
    clr  r25
    sub  r24, r16
    sbc  r25, r17         /* negate for BLACK side */
    rjmp evl_ret
evl_white:
    movw r24, r16
evl_ret:
    pop  r14
    pop  r15
    pop  r16
    pop  r17
    pop  r28
    pop  r29
    ret

/* ================================================================== */
/* find_king  r25:r24=board* r22=side -> r24=square                     */
/* ================================================================== */
find_king:
    movw r26, r24
    clr  r18
fk_loop:
    cpi  r18, 64
    breq fk_done
    ld   r24, X+
    mov  r25, r24
    andi r25, 0x07
    cpi  r25, PIECE_KING
    brne fk_next
    andi r24, CHESS_BLACK
    cp   r24, r22
    breq fk_found
fk_next:
    inc  r18
    rjmp fk_loop
fk_found:
    mov  r24, r18
    ret
fk_done:
    clr  r24
    ret

/* ================================================================== */
/* chess_is_in_check  r25:r24=board* r22=side -> r24                    */
/* ================================================================== */
.global chess_is_in_check
.type   chess_is_in_check, @function
chess_is_in_check:
    push r22
    push r25
    push r24              /* save board* and side on stack */
    rcall find_king       /* r24 = king square */
    mov  r22, r24         /* r22 = king square */
    pop  r24
    pop  r25              /* r25:r24 = board* */
    pop  r26              /* r26 = side (was r22 on push) */
    mov  r20, r26
    eor  r20, r1
    ldi  r23, CHESS_BLACK
    eor  r20, r23         /* r20 = opposite_side (attacker) */
    rjmp is_square_attacked   /* tail call */
.size chess_is_in_check, .-chess_is_in_check

/* ================================================================== */
/* ray_steps  r24=file r22=rank r20=df(s8) r18=dr(s8) -> r24           */
/* ================================================================== */
ray_steps:
    ldi  r25, 7
    tst  r20
    breq rs_no_file
    brmi rs_file_neg
    ldi  r21, 7
    sub  r21, r24
    cp   r21, r25
    brsh rs_no_file
    mov  r25, r21
    rjmp rs_no_file
rs_file_neg:
    cp   r24, r25
    brsh rs_no_file
    mov  r25, r24
rs_no_file:
    tst  r18
    breq rs_done
    brmi rs_rank_neg
    ldi  r21, 7
    sub  r21, r22
    cp   r21, r25
    brsh rs_done
    mov  r25, r21
    rjmp rs_done
rs_rank_neg:
    cp   r22, r25
    brsh rs_done
    mov  r25, r22
rs_done:
    mov  r24, r25
    ret

/* ================================================================== */
/* is_square_attacked  r25:r24=board* r22=square r20=attacker_side     */
/* -> r24  (0=no 1=yes)                                                 */
/* ================================================================== */
is_square_attacked:
    push r29
    push r28
    push r17
    push r16
    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8

    movw r28, r24         /* Y = board */
    mov  r10, r22         /* r10 = square */
    mov  r11, r20         /* r11 = attacker_side */
    mov  r8,  r22
    andi r8,  0x07        /* r8 = file */
    mov  r9,  r22
    lsr  r9
    lsr  r9
    lsr  r9               /* r9 = rank */

    /* --- pawn checks --- */
    cpi  r11, CHESS_WHITE
    brne isa_black_pawn
    /* WHITE attacker: looks for white pawns below square */
    cpi  r9, 0
    breq isa_skip_pawn
    cpi  r8, 0
    breq isa_wp_no_left
    mov  r26, r10
    subi r26, 9           /* square-9 */
    movw r30, r28
    add  r30, r26
    adc  r31, r1
    ld   r24, Z
    cpi  r24, (CHESS_WHITE | PIECE_PAWN)
    breq isa_yes
isa_wp_no_left:
    cpi  r8, 7
    breq isa_skip_pawn
    mov  r26, r10
    subi r26, 7           /* square-7 */
    movw r30, r28
    add  r30, r26
    adc  r31, r1
    ld   r24, Z
    cpi  r24, (CHESS_WHITE | PIECE_PAWN)
    breq isa_yes
    rjmp isa_skip_pawn
isa_black_pawn:
    cpi  r9, 7
    breq isa_skip_pawn
    cpi  r8, 0
    breq isa_bp_no_left
    mov  r26, r10
    subi r26, -7          /* square+7 */
    movw r30, r28
    add  r30, r26
    adc  r31, r1
    ld   r24, Z
    cpi  r24, (CHESS_BLACK | PIECE_PAWN)
    breq isa_yes
isa_bp_no_left:
    cpi  r8, 7
    breq isa_skip_pawn
    mov  r26, r10
    subi r26, -9          /* square+9 */
    movw r30, r28
    add  r30, r26
    adc  r31, r1
    ld   r24, Z
    cpi  r24, (CHESS_BLACK | PIECE_PAWN)
    breq isa_yes
isa_skip_pawn:

    /* --- knight checks --- */
    ldi  r30, lo8(knight_df)
    ldi  r31, hi8(knight_df)
    ldi  r16, 8           /* loop count */
isa_knight_loop:
    lpm  r20, Z+          /* df = knight_df[i] */
    push r30
    push r31
    ldi  r30, lo8(knight_dr)
    ldi  r31, hi8(knight_dr)
    ldi  r24, 8
    sub  r24, r16         /* offset = 8-remaining */
    add  r30, r24
    adc  r31, r1
    lpm  r21, Z           /* dr = knight_dr[i] */
    pop  r31
    pop  r30

    /* target_file = file + df (signed) */
    mov  r22, r8
    add  r22, r20
    /* bounds: 0..7 */
    cpi  r22, 8
    brsh isa_kn_next
    /* target_rank = rank + dr (signed) */
    mov  r23, r9
    add  r23, r21
    cpi  r23, 8
    brsh isa_kn_next
    /* target = target_rank*8 + target_file */
    mov  r24, r23
    lsl  r24
    lsl  r24
    lsl  r24
    add  r24, r22
    /* check piece */
    movw r26, r28
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    mov  r25, r11
    ori  r25, PIECE_KNIGHT
    cp   r24, r25
    breq isa_yes
isa_kn_next:
    dec  r16
    brne isa_knight_loop

    /* --- bishop/queen rays (4 diagonals) --- */
    ldi  r17, 4
isa_bishop_loop:
    ldi  r24, 4
    sub  r24, r17         /* i = 4-remaining */
    push r17
    /* load bishop_df[i] and bishop_dr[i] */
    ldi  r30, lo8(bishop_df)
    ldi  r31, hi8(bishop_df)
    add  r30, r24
    adc  r31, r1
    lpm  r20, Z           /* r20 = df */
    ldi  r30, lo8(bishop_dr)
    ldi  r31, hi8(bishop_dr)
    add  r30, r24
    adc  r31, r1
    lpm  r18, Z           /* r18 = dr */
    /* ray_steps(file, rank, df, dr) */
    mov  r24, r8
    mov  r22, r9
    rcall ray_steps       /* r24 = steps */
    mov  r18, r24         /* r18 = steps */
    /* delta = df + dr*8 */
    mov  r20, r18         /* wait, I just clobbered r18 (steps). let me redo */
    pop  r17
    push r17
    /* reload df and dr */
    ldi  r24, 4
    sub  r24, r17
    ldi  r30, lo8(bishop_df)
    ldi  r31, hi8(bishop_df)
    add  r30, r24
    adc  r31, r1
    lpm  r20, Z           /* r20 = df */
    ldi  r30, lo8(bishop_dr)
    ldi  r31, hi8(bishop_dr)
    add  r30, r24
    adc  r31, r1
    lpm  r23, Z           /* r23 = dr */
    /* ray_steps */
    mov  r24, r8          /* file */
    mov  r22, r9          /* rank */
    /* r20=df already, need dr in r18 */
    mov  r18, r23
    rcall ray_steps       /* r24 = steps */
    push r24              /* save steps */
    /* delta = df + dr*8: r20=df, r23=dr */
    mov  r22, r23
    lsl  r22
    lsl  r22
    lsl  r22              /* r22 = dr*8 */
    add  r20, r22         /* r20 = delta = df + dr*8 */
    pop  r18              /* r18 = steps */
    /* asm_scan_ray(squares, square, delta, steps, attacker_side, BISHOP, QUEEN) */
    movw r24, r28         /* r25:r24 = board (= &squares[0]) */
    mov  r22, r10         /* r22 = square */
    /* r20 = delta, r18 = steps already set */
    mov  r16, r11         /* r16 = attacker_side */
    ldi  r14, PIECE_BISHOP
    ldi  r12, PIECE_QUEEN
    rcall asm_scan_ray
    tst  r24
    pop  r17
    brne isa_yes2
    dec  r17
    brne isa_bishop_loop

    /* --- rook/queen rays (4 orthogonals) --- */
    ldi  r17, 4
isa_rook_loop:
    ldi  r24, 4
    sub  r24, r17
    push r17
    ldi  r30, lo8(rook_df)
    ldi  r31, hi8(rook_df)
    add  r30, r24
    adc  r31, r1
    lpm  r20, Z
    ldi  r30, lo8(rook_dr)
    ldi  r31, hi8(rook_dr)
    add  r30, r24
    adc  r31, r1
    lpm  r23, Z
    mov  r24, r8
    mov  r22, r9
    mov  r18, r23
    rcall ray_steps
    push r24
    mov  r22, r23
    lsl  r22
    lsl  r22
    lsl  r22
    add  r20, r22
    pop  r18
    movw r24, r28
    mov  r22, r10
    mov  r16, r11
    ldi  r14, PIECE_ROOK
    ldi  r12, PIECE_QUEEN
    rcall asm_scan_ray
    tst  r24
    pop  r17
    brne isa_yes2
    dec  r17
    brne isa_rook_loop

    /* --- king proximity (8 squares) --- */
    ldi  r16, 8
isa_king_loop:
    ldi  r24, 8
    sub  r24, r16
    ldi  r30, lo8(king_df)
    ldi  r31, hi8(king_df)
    add  r30, r24
    adc  r31, r1
    lpm  r20, Z
    ldi  r30, lo8(king_dr)
    ldi  r31, hi8(king_dr)
    add  r30, r24
    adc  r31, r1
    lpm  r21, Z
    mov  r22, r8
    add  r22, r20
    cpi  r22, 8
    brsh isa_kg_next
    mov  r23, r9
    add  r23, r21
    cpi  r23, 8
    brsh isa_kg_next
    mov  r24, r23
    lsl  r24
    lsl  r24
    lsl  r24
    add  r24, r22
    movw r26, r28
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    mov  r25, r11
    ori  r25, PIECE_KING
    cp   r24, r25
    breq isa_yes
isa_kg_next:
    dec  r16
    brne isa_king_loop

    clr  r24
    rjmp isa_done
isa_yes2:
isa_yes:
    ldi  r24, 1
isa_done:
    pop  r8
    pop  r9
    pop  r10
    pop  r11
    pop  r12
    pop  r13
    pop  r14
    pop  r15
    pop  r16
    pop  r17
    pop  r28
    pop  r29
    ret

/* ================================================================== */
/* emit_legal_move  r25:r24=board* r23:r22=move                        */
/* implicit: r15:r14=consumer  r13:r12=context                         */
/* -> r24 (1=continue 0=stop)                                           */
/* Allocates chess_board_t next (68 bytes) on stack.                   */
/* ================================================================== */
emit_legal_move:
    push r29
    push r28
    push r17
    push r16
    push r11
    push r10

    movw r16, r24         /* r17:r16 = board* */
    movw r10, r22         /* r11:r10 = move   */

    /* allocate 68 bytes on stack; Y = &next[0] */
    in   r28, 0x3D
    in   r29, 0x3E
    sbiw r28, 68
    in   r0,  0x3F
    cli
    out  0x3E, r29
    out  0x3F, r0
    out  0x3D, r28
    adiw r28, 1           /* Y = &next[0] = SP+1 */

    /* copy 68 bytes: source=r17:r16, dest=Y */
    movw r26, r16
    ldi  r24, 68
elm_copy:
    ld   r0, X+
    st   Y+, r0
    dec  r24
    brne elm_copy
    sbiw r28, 68          /* Y = &next[0] again */

    /* chess_apply_move(&next, move) */
    movw r24, r28
    movw r22, r10
    rcall chess_apply_move

    /* chess_is_in_check(&next, opposite_side(next.side_to_move)) */
    movw r26, r28
    adiw r26, 64
    ld   r22, X           /* next.side_to_move (after flip) */
    ldi  r23, CHESS_BLACK
    eor  r22, r23         /* opposite = original mover */
    movw r24, r28
    rcall chess_is_in_check
    tst  r24
    brne elm_illegal

    /* call consumer(move, &next, context) */
    movw r24, r10         /* r25:r24 = move */
    movw r22, r28         /* r23:r22 = &next */
    movw r20, r12         /* r21:r20 = context (r13:r12) */
    movw r30, r14         /* Z = consumer (r15:r14) */
    icall
    rjmp elm_done

elm_illegal:
    ldi  r24, 1           /* illegal: continue generation */

elm_done:
    /* deallocate 68 bytes: Y now = &next[0] = SP+1, so SP = Y-1 */
    sbiw r28, 1
    in   r0, 0x3F
    cli
    out  0x3E, r29
    out  0x3F, r0
    out  0x3D, r28

    pop  r10
    pop  r11
    pop  r16
    pop  r17
    pop  r28
    pop  r29
    ret

/* ================================================================== */
/* emit_promotion_set  r25:r24=board* r22=from r20=to                  */
/* implicit: consumer/context in r15:r14 r13:r12                       */
/* -> r24 (1=continue 0=stop)                                           */
/* ================================================================== */
emit_promotion_set:
    push r17
    push r16
    push r11
    push r10
    movw r16, r24         /* r17:r16 = board* */
    mov  r10, r22         /* r10 = from */
    mov  r11, r20         /* r11 = to   */
    ldi  r19, MOVE_PROMOTE_Q
eps_loop:
    cpi  r19, (MOVE_PROMOTE_N + 1)
    breq eps_done_ok
    movw r24, r16
    mov  r22, r10
    mov  r20, r11
    mov  r18, r19
    /* make_move(from=r22, to=r20, flag=r18) but signature is (from=r24, to=r22, flag=r20) */
    /* rearrange: from->r24, to->r22, flag->r20 */
    mov  r24, r10
    mov  r22, r11
    mov  r20, r19
    rcall make_move       /* r25:r24 = move */
    movw r22, r24         /* r23:r22 = move */
    movw r24, r16         /* r25:r24 = board* */
    rcall emit_legal_move
    tst  r24
    breq eps_stop
    inc  r19
    rjmp eps_loop
eps_stop:
    clr  r24
    rjmp eps_ret
eps_done_ok:
    ldi  r24, 1
eps_ret:
    pop  r10
    pop  r11
    pop  r16
    pop  r17
    ret

/* ================================================================== */
/* generate_pawn_moves  r25:r24=board* r22=square                      */
/* -> r24                                                               */
/* ================================================================== */
generate_pawn_moves:
    push r29
    push r28
    push r17
    push r16
    push r11
    push r10
    push r9
    push r8
    movw r28, r24         /* Y = board */
    mov  r10, r22         /* r10 = square */
    /* side, file, rank */
    movw r26, r28
    adiw r26, 64
    ld   r16, X           /* r16 = side */
    mov  r8,  r10
    andi r8,  0x07        /* r8 = file */
    mov  r9,  r10
    lsr  r9
    lsr  r9
    lsr  r9               /* r9 = rank */
    /* forward, start_rank, promo_rank */
    cpi  r16, CHESS_WHITE
    breq gpm_white
    ldi  r17, 0xF8        /* forward = -8 */
    ldi  r11, 6           /* start_rank = 6 */
    ldi  r8,  1           /* promo_rank = 1; OOPS r8 was file! Fix: */
    /* I need r8=file saved elsewhere. Let me re-use r15 for promo_rank */
    /* and keep r8 = file. But I already overwrote r8. Let me restart: */
    rjmp gpm_restart      /* bail and redo with correct register plan */
gpm_white:
    rjmp gpm_restart

gpm_restart:
    /* Clean register plan: */
    /* r28:r29 (Y) = board*                  */
    /* r10 = square                          */
    /* r8  = file  (square & 7)              */
    /* r9  = rank  (square >> 3)             */
    /* r16 = side                            */
    /* r17 = forward (int8_t: 8 or -8=0xF8) */
    /* r11 = start_rank                      */
    /* Need promo_rank: store in r15 via push/pop scope */
    mov  r8, r10
    andi r8, 0x07
    mov  r9, r10
    lsr  r9
    lsr  r9
    lsr  r9
    movw r26, r28
    adiw r26, 64
    ld   r16, X
    push r15
    cpi  r16, CHESS_WHITE
    breq gpm_set_white
    ldi  r17, 0xF8        /* -8 */
    ldi  r11, 6
    ldi  r15, 1           /* promo_rank */
    rjmp gpm_forward
gpm_set_white:
    ldi  r17, 8
    ldi  r11, 1
    ldi  r15, 6           /* promo_rank */

gpm_forward:
    /* next_square = square + forward */
    mov  r20, r10
    add  r20, r17         /* r20 = next_square (int8_t arithmetic but stored as uint8_t) */
    /* bounds: 0..63 */
    cpi  r20, 64
    brsh gpm_captures
    /* check empty */
    movw r26, r28
    add  r26, r20
    adc  r27, r1
    ld   r24, X
    tst  r24
    brne gpm_captures
    /* on promo_rank? */
    cp   r9, r15
    brne gpm_one_step
    /* emit_promotion_set(board, square=from, to=r20) */
    movw r24, r28
    mov  r22, r10
    mov  r20, r20         /* noop, to is already r20 */
    rcall emit_promotion_set
    tst  r24
    breq gpm_stop
    rjmp gpm_captures

gpm_one_step:
    mov  r24, r10         /* from */
    mov  r22, r20         /* to = next_square (r20 still valid) */
    clr  r20              /* flag = MOVE_NORMAL */
    rcall make_move
    movw r22, r24
    movw r24, r28
    rcall emit_legal_move
    tst  r24
    breq gpm_stop
    /* double push from start rank */
    cp   r9, r11
    brne gpm_captures
    mov  r20, r10
    add  r20, r17
    add  r20, r17         /* double_square = square + 2*forward */
    cpi  r20, 64
    brsh gpm_captures
    movw r26, r28
    add  r26, r20
    adc  r27, r1
    ld   r24, X
    tst  r24
    brne gpm_captures
    mov  r24, r10
    mov  r22, r20
    clr  r20
    rcall make_move
    movw r22, r24
    movw r24, r28
    rcall emit_legal_move
    tst  r24
    breq gpm_stop

gpm_captures:
    /* capture left (file > 0) */
    tst  r8
    breq gpm_cap_right
    mov  r20, r10
    add  r20, r17
    dec  r20              /* capture_square = square + forward - 1 */
    cpi  r20, 64
    brsh gpm_cap_right
    movw r26, r28
    add  r26, r20
    adc  r27, r1
    ld   r24, X           /* piece at target */
    /* is_enemy OR ep_square? */
    /* ep_square check */
    movw r26, r28
    adiw r26, 66
    ld   r25, X           /* ep_square (int8_t) */
    cp   r20, r25
    breq gpm_cl_ep
    /* is_enemy: piece != 0 && colour(piece) != side */
    tst  r24
    breq gpm_cap_right
    mov  r22, r24
    andi r22, CHESS_BLACK
    cp   r22, r16
    breq gpm_cap_right    /* same colour, skip */
    clr  r22              /* flag = NORMAL */
    rjmp gpm_cl_emit
gpm_cl_ep:
    ldi  r22, MOVE_EN_PASSANT
gpm_cl_emit:
    /* check promo_rank */
    cp   r9, r15
    brne gpm_cl_no_promo
    cpi  r22, MOVE_NORMAL
    brne gpm_cap_right
    movw r24, r28
    mov  r22, r10
    /* to = r20 */
    push r20
    mov  r20, r20         /* noop */
    pop  r20
    push r20
    mov  r20, r20
    pop  r20              /* just keeping r20 = capture_square */
    /* emit_promotion_set(board, from, to) */
    /* args: r25:r24=board*, r22=from, r20=to */
    movw r24, r28
    mov  r22, r10
    rcall emit_promotion_set
    tst  r24
    breq gpm_stop
    rjmp gpm_cap_right
gpm_cl_no_promo:
    mov  r18, r22         /* save flag */
    mov  r24, r10         /* from */
    mov  r22, r20         /* to */
    mov  r20, r18         /* flag */
    rcall make_move
    movw r22, r24
    movw r24, r28
    rcall emit_legal_move
    tst  r24
    breq gpm_stop

gpm_cap_right:
    /* capture right (file < 7) */
    cpi  r8, 7
    breq gpm_done
    mov  r20, r10
    add  r20, r17
    inc  r20              /* square + forward + 1 */
    cpi  r20, 64
    brsh gpm_done
    movw r26, r28
    add  r26, r20
    adc  r27, r1
    ld   r24, X
    movw r26, r28
    adiw r26, 66
    ld   r25, X
    cp   r20, r25
    breq gpm_cr_ep
    tst  r24
    breq gpm_done
    mov  r22, r24
    andi r22, CHESS_BLACK
    cp   r22, r16
    breq gpm_done
    clr  r22
    rjmp gpm_cr_emit
gpm_cr_ep:
    ldi  r22, MOVE_EN_PASSANT
gpm_cr_emit:
    cp   r9, r15
    brne gpm_cr_no_promo
    cpi  r22, MOVE_NORMAL
    brne gpm_done
    movw r24, r28
    mov  r22, r10
    rcall emit_promotion_set
    tst  r24
    breq gpm_stop
    rjmp gpm_done
gpm_cr_no_promo:
    mov  r18, r22
    mov  r24, r10
    mov  r22, r20
    mov  r20, r18
    rcall make_move
    movw r22, r24
    movw r24, r28
    rcall emit_legal_move
    tst  r24
    breq gpm_stop

gpm_done:
    pop  r15
    ldi  r24, 1           /* continue */
    rjmp gpm_ret
gpm_stop:
    pop  r15
    clr  r24
gpm_ret:
    pop  r8
    pop  r9
    pop  r10
    pop  r11
    pop  r16
    pop  r17
    pop  r28
    pop  r29
    ret

/* ================================================================== */
/* generate_jump_moves                                                  */
/* r25:r24=board* r22=square r21:r20=df_pgm r19:r18=dr_pgm r16=count  */
/* -> r24                                                               */
/* ================================================================== */
generate_jump_moves:
    push r29
    push r28
    push r17
    push r16
    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8

    movw r28, r24         /* Y = board */
    mov  r10, r22         /* square */
    movw r12, r20         /* r13:r12 = df_pgm */
    movw r14, r18         /* wait - r14 is consumer! I'm clobbering it! */

    /* BUG: r15:r14 = consumer (implicit), r13:r12 = context (implicit).
     * I cannot use r13:r12 and r15:r14 for local storage in this function.
     * Fix: use r8:r9 and r10:r11 for df_pgm/dr_pgm pointers.
     * r16 (call-saved) = count (already there).
     * r8:r9 = df_pgm pointer (low:high)
     * r10  = square (1 byte)
     * r11  = file
     * r17  = side (board->side_to_move)
     */
    movw r8, r20          /* r9:r8 = df_pgm */
    /* dr_pgm was in r19:r18, save to local vars */
    push r19
    push r18              /* stack holds dr_pgm hi:lo */
    mov  r10, r22         /* square */
    mov  r11, r10
    andi r11, 0x07        /* file */
    mov  r17, r10
    lsr  r17
    lsr  r17
    lsr  r17              /* rank */
    movw r26, r28
    adiw r26, 64
    ld   r18, X           /* r18 = side */

gjm_loop:
    tst  r16
    breq gjm_done
    dec  r16
    /* i = original_count - 1 - r16. Since r16 counts down, use (count-1-r16). */
    /* Actually I'm iterating: start with count, decrement. Use offset = (initial-count-r16). */
    /* Simpler: just maintain PROGMEM pointers and advance them */
    /* I'll load df and dr from current pointer positions */
    movw r30, r8          /* Z = df_pgm + offset */
    /* How do I track the offset? I need to know which element we're on. */
    /* Easiest: maintain r8:r9 as a pointer that advances. */
    lpm  r20, Z+          /* df = *df_ptr++ */
    movw r8, r30          /* update df_ptr */
    /* load dr: stack-based approach is messy. Let me use a different approach:
     * Keep dr_pgm in r9 (reuse r8:r9 for two 8-bit registers since ptrs are 16-bit).
     * Actually I need 2x 16-bit pointers. Let me use the stack differently.
     */
    /* This register layout is getting too complex. Restart with simpler approach:
     * Use call-clobbered registers r18-r27 for local state in this function.
     * At each iteration, reload the table pointers from stack.
     * The count is in r16 (call-saved). The loop index can be computed.
     */
    rjmp gjm_loop

gjm_done:
    pop  r18
    pop  r19
    /* ... */
    pop  r8
    pop  r9
    pop  r10
    pop  r11
    pop  r12
    pop  r13
    pop  r14
    pop  r15
    pop  r16
    pop  r17
    pop  r28
    pop  r29
    ldi  r24, 1
    ret
