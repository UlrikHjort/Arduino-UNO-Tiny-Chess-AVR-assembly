/***************************************************************************
--                      tiny_chess - chess_board
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

#define PIECE_EMPTY    0
#define PIECE_PAWN     1
#define PIECE_KNIGHT   2
#define PIECE_BISHOP   3
#define PIECE_ROOK     4
#define PIECE_QUEEN    5
#define PIECE_KING     6
#define CHESS_WHITE    0
#define CHESS_BLACK    8
#define CASTLE_WHITE_K 1
#define CASTLE_WHITE_Q 2
#define CASTLE_BLACK_K 4
#define CASTLE_BLACK_Q 8
#define MOVE_PROMOTE_Q 4
#define MOVE_PROMOTE_N 7
#define MOVE_EN_PASSANT 3
#define MOVE_CASTLE_K  1
#define MOVE_CASTLE_Q  2

/* Board struct offsets */
#define BOFF_SIDE   64
#define BOFF_CASTLE 65
#define BOFF_EP     66
#define BOFF_CLOCK  67

/* Helper macro: X = board_ptr + offset  (offset may be > 63) */
/* Usage: ldi r24,off; add r26,r24; adc r27,r1  after movw r26,board_reg */

/* ------------------------------------------------------------------ PROGMEM */
.section .progmem.gcc_exc,"a",@progbits

.global initial_board
initial_board:
    .byte 4,2,3,5,6,3,2,4
    .byte 1,1,1,1,1,1,1,1
    .byte 0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0
    .byte 9,9,9,9,9,9,9,9
    .byte 12,10,11,13,14,11,10,12

.global piece_values
piece_values:
    .word 0, 100, 320, 330, 500, 900, 0

.global piece_glyphs
piece_glyphs:
    .byte '.','p','n','b','r','q','k'

.global knight_df
.global knight_dr
knight_df: .byte  1, 2, 2, 1,-1,-2,-2,-1
knight_dr: .byte  2, 1,-1,-2,-2,-1, 1, 2

.global bishop_df
.global bishop_dr
bishop_df: .byte  1, 1,-1,-1
bishop_dr: .byte  1,-1, 1,-1

.global rook_df
.global rook_dr
rook_df:   .byte  1,-1, 0, 0
rook_dr:   .byte  0, 0, 1,-1

.global king_df
.global king_dr
king_df:   .byte  1, 1, 1, 0, 0,-1,-1,-1
king_dr:   .byte  1, 0,-1, 1,-1, 1, 0,-1

.global promoted_type
promoted_type: .byte PIECE_QUEEN, PIECE_ROOK, PIECE_BISHOP, PIECE_KNIGHT

.global promotion_chars
promotion_chars: .byte 'q','r','b','n'

/* ------------------------------------------------------------------ .text */
.text

/* ================================================================
   chess_reset  r25:r24=board*
   ================================================================ */
.global chess_reset
.type   chess_reset, @function
chess_reset:
    push r29
    push r28
    movw r28, r24
    ldi  r30, lo8(initial_board)
    ldi  r31, hi8(initial_board)
    ldi  r18, 64
cr_lp:
    lpm  r24, Z+
    st   Y+, r24
    dec  r18
    brne cr_lp
    st   Y+, r1
    ldi  r24, 0x0F
    st   Y+, r24
    ldi  r24, 0xFF
    st   Y+, r24
    st   Y,  r1
    pop  r28
    pop  r29
    ret
.size chess_reset, .-chess_reset

/* ================================================================
   chess_piece_char  r24=piece -> r24=char
   ================================================================ */
.global chess_piece_char
.type   chess_piece_char, @function
chess_piece_char:
    mov  r25, r24
    tst  r24
    breq cpc_dot
    andi r24, 0x07
    ldi  r30, lo8(piece_glyphs)
    ldi  r31, hi8(piece_glyphs)
    add  r30, r24
    adc  r31, r1
    lpm  r24, Z
    andi r25, CHESS_BLACK
    brne cpc_done
    subi r24, 32
cpc_done:
    ret
cpc_dot:
    ldi  r24, '.'
    ret
.size chess_piece_char, .-chess_piece_char

/* ================================================================
   piece_value_fn  r24=type(0..6) -> r25:r24 (int16_t)
   ================================================================ */
piece_value_fn:
    lsl  r24
    ldi  r30, lo8(piece_values)
    ldi  r31, hi8(piece_values)
    add  r30, r24
    adc  r31, r1
    lpm  r24, Z+
    lpm  r25, Z
    ret

/* ================================================================
   center_bonus  r24=piece r22=square -> r24 (int8_t)
   Clobbers r18-r25
   ================================================================ */
center_bonus:
    mov  r23, r22
    andi r23, 0x07          /* r23 = file */
    lsr  r22
    lsr  r22
    lsr  r22                /* r22 = rank */
    mov  r21, r24
    andi r21, CHESS_BLACK
    andi r24, 0x07          /* r24 = type */
    tst  r21
    breq cb_w
    ldi  r25, 7
    sub  r25, r22
    mov  r20, r25
    rjmp cb_dist
cb_w:
    mov  r20, r22           /* rel_rank */
cb_dist:
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
    add  r18, r19           /* r18 = dist */
    cpi  r24, PIECE_PAWN
    breq cb_p
    cpi  r24, PIECE_KNIGHT
    breq cb_n
    cpi  r24, PIECE_BISHOP
    breq cb_b
    cpi  r24, PIECE_ROOK
    breq cb_r
    cpi  r24, PIECE_QUEEN
    breq cb_q
    cpi  r24, PIECE_KING
    breq cb_k
    clr  r24
    ret
cb_p:
    mov  r24, r20
    lsl  r24
    lsl  r24
    sub  r24, r18
    ret
cb_n:
    mov  r24, r18
    lsl  r24
    lsl  r24
    ldi  r25, 18
    sub  r25, r24
    mov  r24, r25
    ret
cb_b:
    mov  r24, r18
    add  r24, r18
    add  r24, r18
    ldi  r25, 12
    sub  r25, r24
    mov  r24, r25
    ret
cb_r:
    mov  r24, r20
    lsl  r24
    ret
cb_q:
    mov  r24, r18
    lsl  r24
    ldi  r25, 8
    sub  r25, r24
    mov  r24, r25
    ret
cb_k:
    mov  r24, r18
    add  r24, r18
    add  r24, r18
    neg  r24
    ret

/* ================================================================
   evaluate_board  r25:r24=board* -> r25:r24 (int16_t)
   ================================================================ */
.global evaluate_board
.type   evaluate_board, @function
evaluate_board:
    push r17
    push r16
    push r15
    push r14
    push r29
    push r28
    movw r28, r24           /* Y = board */
    clr  r16
    clr  r17                /* score = 0 */
    clr  r14                /* square = 0 */
evl_lp:
    ldi  r25, 64
    cp   r14, r25
    breq evl_done
    movw r26, r28
    add  r26, r14
    adc  r27, r1
    ld   r15, X             /* piece */
    tst  r15
    breq evl_nx
    mov  r24, r15
    andi r24, 0x07
    rcall piece_value_fn    /* r25:r24 = value */
    push r25
    push r24
    mov  r24, r15
    mov  r22, r14
    rcall center_bonus      /* r24 = bonus int8_t */
    mov  r25, r24
    lsl  r25
    sbc  r25, r25           /* sign extend */
    pop  r22
    pop  r23
    add  r22, r24
    adc  r23, r25           /* value += bonus */
    ldi  r25, CHESS_BLACK
    and  r15, r25
    brne evl_sub
    add  r16, r22
    adc  r17, r23
    rjmp evl_nx
evl_sub:
    sub  r16, r22
    sbc  r17, r23
evl_nx:
    inc  r14
    rjmp evl_lp
evl_done:
    movw r26, r28
    ldi  r24, BOFF_SIDE
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    tst  r24
    breq evl_w
    clr  r24
    clr  r25
    sub  r24, r16
    sbc  r25, r17
    rjmp evl_ret
evl_w:
    movw r24, r16
evl_ret:
    pop  r28
    pop  r29
    pop  r14
    pop  r15
    pop  r16
    pop  r17
    ret
.size evaluate_board, .-evaluate_board

/* ================================================================
   find_king  r25:r24=board* r22=side -> r24=square
   ================================================================ */
find_king:
    movw r26, r24
    clr  r18
fk_lp:
    cpi  r18, 64
    breq fk_nf
    ld   r24, X+
    mov  r25, r24
    andi r25, 0x07
    cpi  r25, PIECE_KING
    brne fk_nx
    andi r24, CHESS_BLACK
    cp   r24, r22
    breq fk_f
fk_nx:
    inc  r18
    rjmp fk_lp
fk_f:
    mov  r24, r18
    ret
fk_nf:
    clr  r24
    ret

/* ================================================================
   ray_steps  r24=file r22=rank r20=df r18=dr -> r24
   ================================================================ */
ray_steps:
    ldi  r25, 7
    tst  r20
    breq rs_nf
    brmi rs_fn
    ldi  r21, 7
    sub  r21, r24
    cp   r21, r25
    brsh rs_nf
    mov  r25, r21
    rjmp rs_nf
rs_fn:
    cp   r24, r25
    brsh rs_nf
    mov  r25, r24
rs_nf:
    tst  r18
    breq rs_d
    brmi rs_rn
    ldi  r21, 7
    sub  r21, r22
    cp   r21, r25
    brsh rs_d
    mov  r25, r21
    rjmp rs_d
rs_rn:
    cp   r22, r25
    brsh rs_d
    mov  r25, r22
rs_d:
    mov  r24, r25
    ret

/* ================================================================
   is_square_attacked  r25:r24=board* r22=square r20=attacker_side
   -> r24
   Register plan (saved/restored): r5-r12, r14, r16
     r5=loop_i  r6=rank  r7=file  r8=attacker  r9=square  r10:r11=board
     r12=target_b  r14=target_a  r16=attacker_side (for asm_scan_ray)
   ================================================================ */
.global is_square_attacked
.type   is_square_attacked, @function
is_square_attacked:
    push r16
    push r14
    push r12
    push r11
    push r10
    push r9
    push r8
    push r7
    push r6
    push r5

    movw r10, r24
    mov  r9,  r22
    mov  r8,  r20
    mov  r7,  r22
    ldi  r25, 0x07
    and  r7,  r25
    mov  r6,  r22
    lsr  r6
    lsr  r6
    lsr  r6

    /* --- pawn --- */
    cp   r8, r1
    brne isa_bp
    tst  r6
    breq isa_sp
    tst  r7
    breq isa_wp_r
    mov  r26, r9
    subi r26, 9
    movw r30, r10
    add  r30, r26
    adc  r31, r1
    ld   r24, Z
    cpi  r24, (CHESS_WHITE | PIECE_PAWN)
    brne .+4
    rjmp isa_yes
isa_wp_r:
    ldi  r25, 7
    cp   r7, r25
    breq isa_sp
    mov  r26, r9
    subi r26, 7
    movw r30, r10
    add  r30, r26
    adc  r31, r1
    ld   r24, Z
    cpi  r24, (CHESS_WHITE | PIECE_PAWN)
    brne .+4
    rjmp isa_yes
    rjmp isa_sp
isa_bp:
    ldi  r25, 7
    cp   r6, r25
    breq isa_sp
    tst  r7
    breq isa_bp_r
    mov  r26, r9
    subi r26, -7
    movw r30, r10
    add  r30, r26
    adc  r31, r1
    ld   r24, Z
    cpi  r24, (CHESS_BLACK | PIECE_PAWN)
    brne .+4
    rjmp isa_yes
isa_bp_r:
    ldi  r25, 7
    cp   r7, r25
    breq isa_sp
    mov  r26, r9
    subi r26, -9
    movw r30, r10
    add  r30, r26
    adc  r31, r1
    ld   r24, Z
    cpi  r24, (CHESS_BLACK | PIECE_PAWN)
    brne .+4
    rjmp isa_yes
isa_sp:

    /* --- knights --- */
    clr  r5
isa_kn:
    ldi  r25, 8
    cp   r5, r25
    breq isa_kn_d
    ldi  r30, lo8(knight_df)
    ldi  r31, hi8(knight_df)
    add  r30, r5
    adc  r31, r1
    lpm  r20, Z
    ldi  r30, lo8(knight_dr)
    ldi  r31, hi8(knight_dr)
    add  r30, r5
    adc  r31, r1
    lpm  r21, Z
    mov  r22, r7
    add  r22, r20
    cpi  r22, 8
    brsh isa_kn_nx
    mov  r23, r6
    add  r23, r21
    cpi  r23, 8
    brsh isa_kn_nx
    lsl  r23
    lsl  r23
    lsl  r23
    add  r23, r22
    movw r26, r10
    add  r26, r23
    adc  r27, r1
    ld   r24, X
    mov  r25, r8
    ori  r25, PIECE_KNIGHT
    cp   r24, r25
    brne .+4
    rjmp isa_yes
isa_kn_nx:
    inc  r5
    rjmp isa_kn
isa_kn_d:

    /* --- diagonal rays (bishop/queen) --- */
    clr  r5
    mov  r16, r8
    ldi  r24, PIECE_BISHOP
    mov  r14, r24
    ldi  r24, PIECE_QUEEN
    mov  r12, r24
isa_diag:
    ldi  r25, 4
    cp   r5, r25
    breq isa_diag_d
    ldi  r30, lo8(bishop_df)
    ldi  r31, hi8(bishop_df)
    add  r30, r5
    adc  r31, r1
    lpm  r20, Z
    ldi  r30, lo8(bishop_dr)
    ldi  r31, hi8(bishop_dr)
    add  r30, r5
    adc  r31, r1
    lpm  r18, Z
    mov  r24, r7
    mov  r22, r6
    rcall ray_steps
    push r24
    ldi  r30, lo8(bishop_df)
    ldi  r31, hi8(bishop_df)
    add  r30, r5
    adc  r31, r1
    lpm  r20, Z
    ldi  r30, lo8(bishop_dr)
    ldi  r31, hi8(bishop_dr)
    add  r30, r5
    adc  r31, r1
    lpm  r21, Z
    mov  r22, r21
    lsl  r22
    lsl  r22
    lsl  r22
    add  r20, r22           /* delta = df + dr*8 */
    pop  r18                /* steps */
    movw r24, r10
    mov  r22, r9
    rcall asm_scan_ray
    tst  r24
    breq .+4
    rjmp isa_yes
    inc  r5
    rjmp isa_diag
isa_diag_d:

    /* --- orthogonal rays (rook/queen) --- */
    clr  r5
    ldi  r24, PIECE_ROOK
    mov  r14, r24
    ldi  r24, PIECE_QUEEN
    mov  r12, r24
isa_orth:
    ldi  r25, 4
    cp   r5, r25
    breq isa_orth_d
    ldi  r30, lo8(rook_df)
    ldi  r31, hi8(rook_df)
    add  r30, r5
    adc  r31, r1
    lpm  r20, Z
    ldi  r30, lo8(rook_dr)
    ldi  r31, hi8(rook_dr)
    add  r30, r5
    adc  r31, r1
    lpm  r18, Z
    mov  r24, r7
    mov  r22, r6
    rcall ray_steps
    push r24
    ldi  r30, lo8(rook_df)
    ldi  r31, hi8(rook_df)
    add  r30, r5
    adc  r31, r1
    lpm  r20, Z
    ldi  r30, lo8(rook_dr)
    ldi  r31, hi8(rook_dr)
    add  r30, r5
    adc  r31, r1
    lpm  r21, Z
    mov  r22, r21
    lsl  r22
    lsl  r22
    lsl  r22
    add  r20, r22
    pop  r18
    movw r24, r10
    mov  r22, r9
    rcall asm_scan_ray
    tst  r24
    breq .+4
    rjmp isa_yes
    inc  r5
    rjmp isa_orth
isa_orth_d:

    /* --- king --- */
    clr  r5
isa_kg:
    ldi  r25, 8
    cp   r5, r25
    breq isa_kg_d
    ldi  r30, lo8(king_df)
    ldi  r31, hi8(king_df)
    add  r30, r5
    adc  r31, r1
    lpm  r20, Z
    ldi  r30, lo8(king_dr)
    ldi  r31, hi8(king_dr)
    add  r30, r5
    adc  r31, r1
    lpm  r21, Z
    mov  r22, r7
    add  r22, r20
    cpi  r22, 8
    brsh isa_kg_nx
    mov  r23, r6
    add  r23, r21
    cpi  r23, 8
    brsh isa_kg_nx
    lsl  r23
    lsl  r23
    lsl  r23
    add  r23, r22
    movw r26, r10
    add  r26, r23
    adc  r27, r1
    ld   r24, X
    mov  r25, r8
    ori  r25, PIECE_KING
    cp   r24, r25
    breq isa_yes
isa_kg_nx:
    inc  r5
    rjmp isa_kg
isa_kg_d:
    clr  r24
    rjmp isa_ret
isa_yes:
    ldi  r24, 1
isa_ret:
    pop  r5
    pop  r6
    pop  r7
    pop  r8
    pop  r9
    pop  r10
    pop  r11
    pop  r12
    pop  r14
    pop  r16
    ret
.size is_square_attacked, .-is_square_attacked

/* ================================================================
   chess_is_in_check  r25:r24=board* r22=side -> r24
   ================================================================ */
.global chess_is_in_check
.type   chess_is_in_check, @function
chess_is_in_check:
    push r25
    push r24
    push r22
    rcall find_king
    mov  r22, r24
    pop  r20
    pop  r24
    pop  r25
    ldi  r18, CHESS_BLACK
    eor  r20, r18
    rjmp is_square_attacked
.size chess_is_in_check, .-chess_is_in_check

/* ================================================================
   chess_apply_move  r25:r24=board*  r23:r22=move
   Register plan (saved): r4-r11
     r11:r10=board  r9=from  r8=to  r7=flag  r6=piece  r5=captured  r4=type
   ================================================================ */
.global chess_apply_move
.type   chess_apply_move, @function
chess_apply_move:
    push r11
    push r10
    push r9
    push r8
    push r7
    push r6
    push r5
    push r4

    movw r10, r24

    /* from = move & 0x3F */
    mov  r9, r22
    ldi  r25, 0x3F
    and  r9, r25

    /* flag = hi nibble of move_hi */
    mov  r24, r23
    swap r24
    andi r24, 0x0F
    mov  r7, r24

    /* to = (move >> 6) & 0x3F */
    mov  r24, r22
    mov  r25, r23
    lsr  r25
    ror  r24
    lsr  r25
    ror  r24
    lsr  r25
    ror  r24
    lsr  r25
    ror  r24
    lsr  r25
    ror  r24
    lsr  r25
    ror  r24
    andi r24, 0x3F
    mov  r8, r24

    /* piece = squares[from] */
    movw r26, r10
    add  r26, r9
    adc  r27, r1
    ld   r6, X

    /* captured = squares[to] */
    movw r26, r10
    add  r26, r8
    adc  r27, r1
    ld   r5, X

    /* type = piece & 7 */
    mov  r4, r6
    ldi  r25, 0x07
    and  r4, r25

    /* halfmove_clock update */
    movw r26, r10
    ldi  r24, BOFF_CLOCK
    add  r26, r24
    adc  r27, r1
    tst  r5
    brne cam_clk_rst
    ldi  r25, PIECE_PAWN
    cp   r4, r25
    brne cam_clk_inc
cam_clk_rst:
    st   X, r1
    rjmp cam_clk_d
cam_clk_inc:
    ld   r24, X
    inc  r24
    st   X, r24
cam_clk_d:

    /* squares[from] = 0 */
    movw r26, r10
    add  r26, r9
    adc  r27, r1
    st   X, r1

    /* ep_square = -1 */
    movw r26, r10
    ldi  r24, BOFF_EP
    add  r26, r24
    adc  r27, r1
    ldi  r24, 0xFF
    st   X, r24

    /* EN_PASSANT: clear the captured pawn */
    ldi  r25, MOVE_EN_PASSANT
    cp   r7, r25
    brne cam_nep
    mov  r24, r6
    andi r24, CHESS_BLACK
    tst  r24
    brne cam_ep_b
    mov  r24, r8
    subi r24, 8
    rjmp cam_ep_clr
cam_ep_b:
    mov  r24, r8
    subi r24, -8
cam_ep_clr:
    movw r26, r10
    add  r26, r24
    adc  r27, r1
    st   X, r1
cam_nep:

    /* KING: update castling, move rook */
    ldi  r25, PIECE_KING
    cp   r4, r25
    breq .+4
    rjmp cam_nkg
    movw r26, r10
    ldi  r24, BOFF_CASTLE
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    mov  r25, r6
    andi r25, CHESS_BLACK
    tst  r25
    brne cam_kg_b
    andi r24, ~(CASTLE_WHITE_K | CASTLE_WHITE_Q)
    rjmp cam_kg_cas
cam_kg_b:
    andi r24, ~(CASTLE_BLACK_K | CASTLE_BLACK_Q)
cam_kg_cas:
    st   X, r24
    ldi  r25, MOVE_CASTLE_K
    cp   r7, r25
    brne cam_cq
    /* castle kingside: rook from sq+3 to sq+1 */
    mov  r24, r6
    andi r24, CHESS_BLACK
    tst  r24
    brne cam_ck_b
    /* white: sq[5]=sq[7], sq[7]=0 */
    movw r26, r10
    adiw r26, 7
    ld   r24, X
    movw r26, r10
    adiw r26, 5
    st   X, r24
    movw r26, r10
    adiw r26, 7
    st   X, r1
    rjmp cam_nkg
cam_ck_b:
    movw r26, r10
    ldi  r24, 63
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    movw r26, r10
    ldi  r25, 61
    add  r26, r25
    adc  r27, r1
    st   X, r24
    movw r26, r10
    ldi  r24, 63
    add  r26, r24
    adc  r27, r1
    st   X, r1
    rjmp cam_nkg
cam_cq:
    ldi  r25, MOVE_CASTLE_Q
    cp   r7, r25
    brne cam_nkg
    mov  r24, r6
    andi r24, CHESS_BLACK
    tst  r24
    brne cam_cq_b
    /* white: sq[3]=sq[0], sq[0]=0 */
    movw r26, r10
    ld   r24, X
    movw r26, r10
    adiw r26, 3
    st   X, r24
    movw r26, r10
    st   X, r1
    rjmp cam_nkg
cam_cq_b:
    movw r26, r10
    ldi  r24, 56
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    movw r26, r10
    ldi  r25, 59
    add  r26, r25
    adc  r27, r1
    st   X, r24
    movw r26, r10
    ldi  r24, 56
    add  r26, r24
    adc  r27, r1
    st   X, r1
cam_nkg:

    /* ROOK: strip castling right */
    ldi  r25, PIECE_ROOK
    cp   r4, r25
    brne cam_nr
    movw r26, r10
    ldi  r24, BOFF_CASTLE
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    cp   r9, r1
    brne cam_r1
    andi r24, ~CASTLE_WHITE_Q
    rjmp cam_r_st
cam_r1:
    ldi  r25, 7
    cp   r9, r25
    brne cam_r2
    andi r24, ~CASTLE_WHITE_K
    rjmp cam_r_st
cam_r2:
    ldi  r25, 56
    cp   r9, r25
    brne cam_r3
    andi r24, ~CASTLE_BLACK_Q
    rjmp cam_r_st
cam_r3:
    ldi  r25, 63
    cp   r9, r25
    brne cam_r_d
    andi r24, ~CASTLE_BLACK_K
cam_r_st:
    movw r26, r10
    ldi  r24, BOFF_CASTLE
    add  r26, r24
    adc  r27, r1
    st   X, r24
cam_r_d:
cam_nr:

    /* Captured rook: strip castling right */
    tst  r5
    breq cam_ncr
    mov  r24, r5
    andi r24, 0x07
    cpi  r24, PIECE_ROOK
    brne cam_ncr
    movw r26, r10
    ldi  r24, BOFF_CASTLE
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    cp   r8, r1
    brne cam_cr1
    andi r24, ~CASTLE_WHITE_Q
    rjmp cam_cr_st
cam_cr1:
    ldi  r25, 7
    cp   r8, r25
    brne cam_cr2
    andi r24, ~CASTLE_WHITE_K
    rjmp cam_cr_st
cam_cr2:
    ldi  r25, 56
    cp   r8, r25
    brne cam_cr3
    andi r24, ~CASTLE_BLACK_Q
    rjmp cam_cr_st
cam_cr3:
    ldi  r25, 63
    cp   r8, r25
    brne cam_cr_d
    andi r24, ~CASTLE_BLACK_K
cam_cr_st:
    movw r26, r10
    ldi  r24, BOFF_CASTLE
    add  r26, r24
    adc  r27, r1
    st   X, r24
cam_cr_d:
cam_ncr:

    /* Double pawn push: set ep_square */
    ldi  r25, PIECE_PAWN
    cp   r4, r25
    brne cam_npp
    mov  r24, r8
    sub  r24, r9
    cpi  r24, 16
    breq cam_ep_set
    cpi  r24, 0xF0
    brne cam_npp
cam_ep_set:
    mov  r24, r9
    add  r24, r8
    lsr  r24
    movw r26, r10
    ldi  r25, BOFF_EP
    add  r26, r25
    adc  r27, r1
    st   X, r24
cam_npp:

    /* Place piece (handle promotion) */
    ldi  r25, MOVE_PROMOTE_Q
    cp   r7, r25
    brlo cam_np
    ldi  r25, (MOVE_PROMOTE_N + 1)
    cp   r7, r25
    brsh cam_np
    mov  r24, r7
    subi r24, MOVE_PROMOTE_Q
    ldi  r30, lo8(promoted_type)
    ldi  r31, hi8(promoted_type)
    add  r30, r24
    adc  r31, r1
    lpm  r24, Z
    mov  r25, r6
    andi r25, CHESS_BLACK
    or   r24, r25
    rjmp cam_pl
cam_np:
    mov  r24, r6
cam_pl:
    movw r26, r10
    add  r26, r8
    adc  r27, r1
    st   X, r24

    /* Flip side_to_move */
    movw r26, r10
    ldi  r24, BOFF_SIDE
    add  r26, r24
    adc  r27, r1
    ld   r24, X
    ldi  r25, CHESS_BLACK
    eor  r24, r25
    st   X, r24

    pop  r4
    pop  r5
    pop  r6
    pop  r7
    pop  r8
    pop  r9
    pop  r10
    pop  r11
    ret
.size chess_apply_move, .-chess_apply_move
