/***************************************************************************
--                      tiny_chess - chess_gen
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
 * Implicit register convention for the generator chain:
 *   r15:r14 = consumer function pointer
 *   r13:r12 = context pointer
 * Set by for_each_legal_move, read only by emit_legal_move.
 * No generator function touches r12..r15.
 */

#define PIECE_EMPTY     0
#define PIECE_PAWN      1
#define PIECE_KNIGHT    2
#define PIECE_BISHOP    3
#define PIECE_ROOK      4
#define PIECE_QUEEN     5
#define PIECE_KING      6
#define CHESS_WHITE     0
#define CHESS_BLACK     8
#define MOVE_NORMAL     0
#define MOVE_CASTLE_K   1
#define MOVE_CASTLE_Q   2
#define MOVE_EN_PASSANT 3
#define MOVE_PROMOTE_Q  4
#define MOVE_PROMOTE_N  7
#define BOFF_SIDE   64
#define BOFF_CASTLE 65
#define BOFF_EP     66

.text

/* ================================================================
   make_move  r24=from  r22=to  r20=flag  -> r25:r24
   ================================================================ */
make_move:
    /* lo byte: from[5:0] | (to[1:0] << 6) */
    mov   r25, r22
    andi  r25, 0x03
    lsl   r25
    lsl   r25
    lsl   r25
    lsl   r25
    lsl   r25
    lsl   r25
    or    r24, r25
    /* hi byte: to[5:2] | (flag[3:0] << 4) */
    mov   r25, r22
    lsr   r25
    lsr   r25
    andi  r25, 0x0F
    mov   r19, r20
    andi  r19, 0x0F
    swap  r19
    or    r25, r19
    ret

/* ================================================================
   emit_legal_move  r25:r24=board*  r23:r22=move
   Implicit: r15:r14=consumer  r13:r12=context
   Allocates 68-byte chess_board_t on stack, copies board, applies
   move, checks legality, calls consumer if legal.
   Returns consumer result (1=continue, 0=stop), or 1 on illegal.
   Saved: r29,r28,r11,r10,r9,r8,r7,r6
     r11:r10=board*  r9=move_hi  r8=move_lo  r7:r6=saved_SP
   ================================================================ */
.global emit_legal_move
emit_legal_move:
    push  r29
    push  r28
    push  r11
    push  r10
    push  r9
    push  r8
    push  r7
    push  r6

    movw  r10, r24           /* board* */
    mov   r8,  r22           /* move lo */
    mov   r9,  r23           /* move hi */

    /* save SP */
    in    r6,  0x3D          /* SPL */
    in    r7,  0x3E          /* SPH */

    /* allocate 68 bytes: SP -= 68 */
    movw  r28, r6            /* Y = old SP (r29=r7, r28=r6) */
    ldi   r24, 68
    sub   r28, r24
    sbc   r29, r1
    in    r0,  0x3F          /* save SREG */
    cli
    out   0x3E, r29          /* SPH first */
    out   0x3D, r28          /* SPL second */
    out   0x3F, r0           /* restore SREG last */
    adiw  r28, 1             /* Y = &next[0] */

    /* copy board -> next (68 bytes) */
    movw  r26, r10
    ldi   r24, 68
elm_cp:
    ld    r0,  X+
    st    Y+,  r0
    dec   r24
    brne  elm_cp
    sbiw  r28, 63
    sbiw  r28, 5             /* Y -= 68  ->  Y = &next[0] */

    /* chess_apply_move(&next, move) - does not use Y */
    movw  r24, r28
    mov   r22, r8
    mov   r23, r9
    rcall chess_apply_move

    /* find the mover's side: after apply, side_to_move flipped to opponent.
       mover = new_side XOR CHESS_BLACK */
    movw  r26, r28
    ldi   r24, BOFF_SIDE
    add   r26, r24
    adc   r27, r1
    ld    r22, X             /* new side_to_move */
    ldi   r24, CHESS_BLACK
    eor   r22, r24           /* mover side */

    /* chess_is_in_check(&next, mover): illegal if mover left king in check */
    movw  r24, r28
    rcall chess_is_in_check
    tst   r24
    brne  elm_ill

    /* call consumer(move, &next, context) */
    mov   r24, r8
    mov   r25, r9
    movw  r22, r28           /* &next */
    movw  r20, r12           /* context from implicit r13:r12 */
    movw  r30, r14           /* consumer from implicit r15:r14 */
    icall
    rjmp  elm_done

elm_ill:
    ldi   r24, 1             /* illegal -> return "continue" */

elm_done:
    mov   r25, r24           /* save return value across SP restore */
    movw  r28, r6            /* Y = old SP (r29=r7, r28=r6) */
    in    r0,  0x3F
    cli
    out   0x3E, r29          /* SPH */
    out   0x3D, r28          /* SPL */
    out   0x3F, r0           /* restore SREG */
    mov   r24, r25

    pop   r6
    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    pop   r28
    pop   r29
    ret

/* ================================================================
   emit_promotion_set  r25:r24=board*  r22=from  r20=to  -> r24
   Loops PROMOTE_Q..PROMOTE_N, calls make_move + emit_legal_move.
   Saved: r11,r10,r9,r8,r7
     r11:r10=board  r9=from  r8=to  r7=flag
   ================================================================ */
emit_promotion_set:
    push  r11
    push  r10
    push  r9
    push  r8
    push  r7

    movw  r10, r24
    mov   r9,  r22
    mov   r8,  r20
    ldi   r24, MOVE_PROMOTE_Q
    mov   r7,  r24

eps_lp:
    ldi   r25, (MOVE_PROMOTE_N + 1)
    cp    r7,  r25
    breq  eps_ok
    mov   r24, r9
    mov   r22, r8
    mov   r20, r7
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    breq  eps_stop
    inc   r7
    rjmp  eps_lp

eps_ok:
    ldi   r24, 1
    rjmp  eps_ret
eps_stop:
    clr   r24
eps_ret:
    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    ret

/* ================================================================
   generate_pawn_moves  r25:r24=board*  r22=square  -> r24
   Saved: r29,r28,r11,r10,r9,r8,r7,r6,r5,r4,r3,r2
     r11:r10=board  r9=square  r8=side  r7=file  r6=rank
     r5=forward(int8)  r4=start_rank  r3=promo_rank  r2=next_sq
   ================================================================ */
generate_pawn_moves:
    push  r29
    push  r28
    push  r11
    push  r10
    push  r9
    push  r8
    push  r7
    push  r6
    push  r5
    push  r4
    push  r3
    push  r2

    movw  r10, r24
    mov   r9,  r22

    /* file = square & 7, rank = square >> 3 */
    mov   r7,  r22
    ldi   r25, 0x07
    and   r7,  r25
    mov   r6,  r22
    lsr   r6
    lsr   r6
    lsr   r6

    /* side from board[BOFF_SIDE] */
    movw  r26, r10
    ldi   r24, BOFF_SIDE
    add   r26, r24
    adc   r27, r1
    ld    r8,  X

    cp    r8,  r1
    breq  gpm_white
    ldi   r24, 0xF8
    mov   r5,  r24           /* forward = -8 */
    ldi   r24, 6
    mov   r4,  r24           /* start_rank for black */
    ldi   r24, 1
    mov   r3,  r24           /* promo_rank  for black */
    rjmp  gpm_fwd
gpm_white:
    ldi   r24, 8
    mov   r5,  r24
    ldi   r24, 1
    mov   r4,  r24
    ldi   r24, 6
    mov   r3,  r24

gpm_fwd:
    /* r2 = next_sq = square + forward */
    mov   r2,  r9
    add   r2,  r5
    ldi   r25, 64
    cp    r2,  r25
    brlo  .+4
    rjmp  gpm_caps           /* out of range (catches -8 wrap too) */

    /* square must be empty */
    movw  r26, r10
    add   r26, r2
    adc   r27, r1
    ld    r24, X
    tst   r24
    breq  .+4
    rjmp  gpm_caps

    /* promotion? */
    cp    r6,  r3
    brne  gpm_one
    movw  r24, r10
    mov   r22, r9
    mov   r20, r2
    rcall emit_promotion_set
    tst   r24
    brne  .+4
    rjmp  gpm_stop
    rjmp  gpm_caps

gpm_one:
    /* single push */
    mov   r24, r9
    mov   r22, r2
    clr   r20
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    brne  .+4
    rjmp  gpm_stop

    /* double push from start rank */
    cp    r6,  r4
    brne  gpm_caps
    mov   r24, r2
    add   r24, r5            /* double_sq */
    cpi   r24, 64
    brsh  gpm_caps
    movw  r26, r10
    add   r26, r24
    adc   r27, r1
    ld    r25, X
    tst   r25
    brne  gpm_caps
    mov   r22, r24
    mov   r24, r9
    clr   r20
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    brne  .+4
    rjmp  gpm_stop

gpm_caps:
    /* ----- capture left (requires file > 0) ----- */
    tst   r7
    breq  gpm_cap_r

    mov   r24, r9
    add   r24, r5
    dec   r24                /* cap_sq = square + forward - 1 */
    cpi   r24, 64
    brsh  gpm_cap_r

    movw  r26, r10
    add   r26, r24
    adc   r27, r1
    ld    r25, X             /* piece at cap_sq */

    movw  r26, r10
    ldi   r20, BOFF_EP
    add   r26, r20
    adc   r27, r1
    ld    r20, X             /* ep_square */

    cp    r24, r20
    breq  gpm_cl_ep
    tst   r25
    breq  gpm_cap_r          /* empty and not ep */
    mov   r22, r25
    andi  r22, CHESS_BLACK
    cp    r22, r8
    breq  gpm_cap_r          /* same colour */
    clr   r20                /* flag = NORMAL */
    rjmp  gpm_cl_emit

gpm_cl_ep:
    ldi   r20, MOVE_EN_PASSANT

gpm_cl_emit:
    /* r24=cap_sq  r20=flag */
    cp    r6,  r3
    brne  gpm_cl_mv
    /* promotion capture: ep on promo rank impossible, flag must be NORMAL */
    mov   r20, r24           /* to = cap_sq */
    movw  r24, r10
    mov   r22, r9            /* from */
    rcall emit_promotion_set
    tst   r24
    brne  .+4
    rjmp  gpm_stop
    rjmp  gpm_cap_r

gpm_cl_mv:
    /* r24=cap_sq  r20=flag  (no push/pop needed - clean register use) */
    mov   r22, r24           /* to = cap_sq */
    mov   r24, r9            /* from = square */
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    brne  .+4
    rjmp  gpm_stop

    /* ----- capture right (requires file < 7) ----- */
gpm_cap_r:
    ldi   r25, 7
    cp    r7,  r25
    breq  gpm_done

    mov   r24, r9
    add   r24, r5
    inc   r24                /* cap_sq = square + forward + 1 */
    cpi   r24, 64
    brsh  gpm_done

    movw  r26, r10
    add   r26, r24
    adc   r27, r1
    ld    r25, X

    movw  r26, r10
    ldi   r20, BOFF_EP
    add   r26, r20
    adc   r27, r1
    ld    r20, X

    cp    r24, r20
    breq  gpm_cr_ep
    tst   r25
    breq  gpm_done
    mov   r22, r25
    andi  r22, CHESS_BLACK
    cp    r22, r8
    breq  gpm_done
    clr   r20
    rjmp  gpm_cr_emit

gpm_cr_ep:
    ldi   r20, MOVE_EN_PASSANT

gpm_cr_emit:
    /* r24=cap_sq  r20=flag */
    cp    r6,  r3
    brne  gpm_cr_mv
    mov   r20, r24
    movw  r24, r10
    mov   r22, r9
    rcall emit_promotion_set
    tst   r24
    breq  gpm_stop
    rjmp  gpm_done

gpm_cr_mv:
    mov   r22, r24           /* to */
    mov   r24, r9            /* from */
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    breq  gpm_stop

gpm_done:
    ldi   r24, 1
    rjmp  gpm_ret
gpm_stop:
    clr   r24
gpm_ret:
    pop   r2
    pop   r3
    pop   r4
    pop   r5
    pop   r6
    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    pop   r28
    pop   r29
    ret

/* ================================================================
   generate_jump_moves
   r25:r24=board*  r22=square  r21:r20=df_pgm  r19:r18=dr_pgm  r16=count
   -> r24
   Saved: r11,r10,r9,r8,r7,r6,r5,r4,r3,r2
     r11:r10=board  r9=square  r8=side  r7=loop_i  r6=count
     r5:r4=df_pgm  r3:r2=dr_pgm
   ================================================================ */
generate_jump_moves:
    push  r11
    push  r10
    push  r9
    push  r8
    push  r7
    push  r6
    push  r5
    push  r4
    push  r3
    push  r2

    movw  r10, r24
    mov   r9,  r22
    movw  r4,  r20           /* r5:r4 = df_pgm */
    movw  r2,  r18           /* r3:r2 = dr_pgm */
    mov   r6,  r16           /* count */
    clr   r7                 /* i = 0 */

    movw  r26, r10
    ldi   r24, BOFF_SIDE
    add   r26, r24
    adc   r27, r1
    ld    r8,  X

gjm_lp:
    cp    r7,  r6
    breq  gjm_done

    movw  r30, r4
    add   r30, r7
    adc   r31, r5
    lpm   r20, Z             /* df */

    movw  r30, r2
    add   r30, r7
    adc   r31, r3
    lpm   r21, Z             /* dr */

    /* target_file = (file + df) - treated as uint8, bounds-checked */
    mov   r22, r9
    andi  r22, 0x07
    add   r22, r20
    cpi   r22, 8
    brsh  gjm_nx

    mov   r23, r9
    lsr   r23
    lsr   r23
    lsr   r23
    add   r23, r21
    cpi   r23, 8
    brsh  gjm_nx

    /* target = rank*8 + file */
    lsl   r23
    lsl   r23
    lsl   r23
    add   r23, r22

    movw  r26, r10
    add   r26, r23
    adc   r27, r1
    ld    r24, X             /* piece at target */

    tst   r24
    breq  gjm_emit
    mov   r25, r24
    andi  r25, CHESS_BLACK
    cp    r25, r8
    breq  gjm_nx             /* same colour */

gjm_emit:
    mov   r24, r9            /* from */
    mov   r22, r23           /* to */
    clr   r20
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    breq  gjm_stop

gjm_nx:
    inc   r7
    rjmp  gjm_lp

gjm_done:
    ldi   r24, 1
    rjmp  gjm_ret
gjm_stop:
    clr   r24
gjm_ret:
    pop   r2
    pop   r3
    pop   r4
    pop   r5
    pop   r6
    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    ret

/* ================================================================
   generate_slider_moves
   r25:r24=board*  r22=square  r21:r20=df_pgm  r19:r18=dr_pgm  r16=count
   -> r24
   Saved: r11,r10,r9,r8,r7,r6,r5,r4,r3,r2
     r11:r10=board  r9=square  r8=side  r7=outer_i  r6=count
     r5:r4=df_pgm base
     r3:r2=dr_pgm base - pushed around inner loop to free r2,r3
       for df_cur (r2) and dr_cur (r3) within each ray
   ================================================================ */
generate_slider_moves:
    push  r11
    push  r10
    push  r9
    push  r8
    push  r7
    push  r6
    push  r5
    push  r4
    push  r3
    push  r2

    movw  r10, r24
    mov   r9,  r22
    movw  r4,  r20           /* r5:r4 = df_pgm */
    movw  r2,  r18           /* r3:r2 = dr_pgm */
    mov   r6,  r16
    clr   r7

    movw  r26, r10
    ldi   r24, BOFF_SIDE
    add   r26, r24
    adc   r27, r1
    ld    r8,  X

gsm_outer:
    cp    r7,  r6
    brne  .+4
    rjmp  gsm_done

    movw  r30, r4
    add   r30, r7
    adc   r31, r5
    lpm   r20, Z             /* df */

    movw  r30, r2
    add   r30, r7
    adc   r31, r3
    lpm   r21, Z             /* dr */

    /* push dr_pgm ptr; use r3:r2 for df_cur/dr_cur in inner loop */
    push  r3
    push  r2
    mov   r2,  r20           /* r2 = df_cur */
    mov   r3,  r21           /* r3 = dr_cur */

    /* inner loop init: target_file, target_rank start one step out */
    mov   r18, r9
    andi  r18, 0x07
    add   r18, r2            /* r18 = target_file */
    mov   r19, r9
    lsr   r19
    lsr   r19
    lsr   r19
    add   r19, r3            /* r19 = target_rank */

gsm_inner:
    cpi   r18, 8
    brsh  gsm_inner_done
    cpi   r19, 8
    brsh  gsm_inner_done

    mov   r24, r19
    lsl   r24
    lsl   r24
    lsl   r24
    add   r24, r18           /* target square index */

    movw  r26, r10
    add   r26, r24
    adc   r27, r1
    ld    r25, X             /* piece at target */

    tst   r25
    breq  gsm_emit
    mov   r20, r25
    andi  r20, CHESS_BLACK
    cp    r20, r8
    breq  gsm_inner_done     /* same colour: ray blocked */

gsm_emit:
    /* r18,r19 are call-clobbered - save across sub-calls */
    push  r25                /* piece (to detect capture) */
    push  r19                /* target_rank */
    push  r18                /* target_file */

    mov   r22, r24           /* to */
    mov   r24, r9            /* from */
    clr   r20
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move

    pop   r18
    pop   r19
    pop   r25

    tst   r24
    breq  gsm_stop_inner

    tst   r25                /* was capture? */
    brne  gsm_inner_done     /* yes: ray ends after capture */

    add   r18, r2            /* advance along ray */
    add   r19, r3
    rjmp  gsm_inner

gsm_stop_inner:
    pop   r2                 /* restore dr_pgm ptr */
    pop   r3
    rjmp  gsm_stop

gsm_inner_done:
    pop   r2
    pop   r3
    inc   r7
    rjmp  gsm_outer

gsm_done:
    ldi   r24, 1
    rjmp  gsm_ret
gsm_stop:
    clr   r24
gsm_ret:
    pop   r2
    pop   r3
    pop   r4
    pop   r5
    pop   r6
    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    ret

/* ================================================================
   generate_castling  r25:r24=board*  r22=square  -> r24
   Saved: r11,r10,r9,r8,r7
     r11:r10=board  r9=square  r8=side  r7=castling
   ================================================================ */
generate_castling:
    push  r11
    push  r10
    push  r9
    push  r8
    push  r7

    movw  r10, r24
    mov   r9,  r22

    movw  r26, r10
    ldi   r24, BOFF_SIDE
    add   r26, r24
    adc   r27, r1
    ld    r8,  X

    /* no castling if already in check */
    movw  r24, r10
    mov   r22, r8
    rcall chess_is_in_check
    tst   r24
    breq  .+4
    rjmp  gc_ok

    movw  r26, r10
    ldi   r24, BOFF_CASTLE
    add   r26, r24
    adc   r27, r1
    ld    r7,  X

    cp    r8,  r1
    brne  .+4
    rjmp  gc_white

    /* ----- black (king must be on e8 = sq 60) ----- */
    ldi   r25, 60
    cp    r9,  r25
    breq  .+4
    rjmp  gc_ok

    /* black kingside: bit 2, squares 61 and 62 empty, not attacked */
    sbrs  r7,  2
    rjmp  gc_bq
    movw  r26, r10
    ldi   r24, 61
    add   r26, r24
    adc   r27, r1
    ld    r24, X
    tst   r24
    brne  gc_bq
    movw  r26, r10
    ldi   r24, 62
    add   r26, r24
    adc   r27, r1
    ld    r24, X
    tst   r24
    brne  gc_bq
    movw  r24, r10
    ldi   r22, 61
    ldi   r20, CHESS_WHITE
    rcall is_square_attacked
    tst   r24
    brne  gc_bq
    movw  r24, r10
    ldi   r22, 62
    ldi   r20, CHESS_WHITE
    rcall is_square_attacked
    tst   r24
    brne  gc_bq
    ldi   r24, 60
    ldi   r22, 62
    ldi   r20, MOVE_CASTLE_K
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    brne  .+4
    rjmp  gc_stop

gc_bq:
    /* black queenside: bit 3, squares 57,58,59 empty, 58 and 59 not attacked */
    sbrs  r7,  3
    rjmp  gc_ok
    movw  r26, r10
    ldi   r24, 57
    add   r26, r24
    adc   r27, r1
    ld    r24, X
    tst   r24
    breq  .+4
    rjmp  gc_ok
    movw  r26, r10
    ldi   r24, 58
    add   r26, r24
    adc   r27, r1
    ld    r24, X
    tst   r24
    breq  .+4
    rjmp  gc_ok
    movw  r26, r10
    ldi   r24, 59
    add   r26, r24
    adc   r27, r1
    ld    r24, X
    tst   r24
    breq  .+4
    rjmp  gc_ok
    movw  r24, r10
    ldi   r22, 59
    ldi   r20, CHESS_WHITE
    rcall is_square_attacked
    tst   r24
    breq  .+4
    rjmp  gc_ok
    movw  r24, r10
    ldi   r22, 58
    ldi   r20, CHESS_WHITE
    rcall is_square_attacked
    tst   r24
    breq  .+4
    rjmp  gc_ok
    ldi   r24, 60
    ldi   r22, 58
    ldi   r20, MOVE_CASTLE_Q
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    brne  .+4
    rjmp  gc_stop
    rjmp  gc_ok

gc_white:
    /* ----- white (king must be on e1 = sq 4) ----- */
    ldi   r25, 4
    cp    r9,  r25
    breq  .+4
    rjmp  gc_ok

    /* white kingside: bit 0, squares 5 and 6 empty, not attacked */
    sbrs  r7,  0
    rjmp  gc_wq
    movw  r26, r10
    adiw  r26, 5
    ld    r24, X
    tst   r24
    brne  gc_wq
    movw  r26, r10
    adiw  r26, 6
    ld    r24, X
    tst   r24
    brne  gc_wq
    movw  r24, r10
    ldi   r22, 5
    ldi   r20, CHESS_BLACK
    rcall is_square_attacked
    tst   r24
    brne  gc_wq
    movw  r24, r10
    ldi   r22, 6
    ldi   r20, CHESS_BLACK
    rcall is_square_attacked
    tst   r24
    brne  gc_wq
    ldi   r24, 4
    ldi   r22, 6
    ldi   r20, MOVE_CASTLE_K
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    brne  .+4
    rjmp  gc_stop

gc_wq:
    /* white queenside: bit 1, squares 1,2,3 empty, 2 and 3 not attacked */
    sbrs  r7,  1
    rjmp  gc_ok
    movw  r26, r10
    adiw  r26, 1
    ld    r24, X
    tst   r24
    breq  .+4
    rjmp  gc_ok
    movw  r26, r10
    adiw  r26, 2
    ld    r24, X
    tst   r24
    breq  .+4
    rjmp  gc_ok
    movw  r26, r10
    adiw  r26, 3
    ld    r24, X
    tst   r24
    breq  .+4
    rjmp  gc_ok
    movw  r24, r10
    ldi   r22, 3
    ldi   r20, CHESS_BLACK
    rcall is_square_attacked
    tst   r24
    breq  .+4
    rjmp  gc_ok
    movw  r24, r10
    ldi   r22, 2
    ldi   r20, CHESS_BLACK
    rcall is_square_attacked
    tst   r24
    breq  .+4
    rjmp  gc_ok
    ldi   r24, 4
    ldi   r22, 2
    ldi   r20, MOVE_CASTLE_Q
    rcall make_move
    movw  r22, r24
    movw  r24, r10
    rcall emit_legal_move
    tst   r24
    brne  .+4
    rjmp  gc_stop

gc_ok:
    ldi   r24, 1
    rjmp  gc_ret
gc_stop:
    clr   r24
gc_ret:
    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    ret

/* ================================================================
   for_each_legal_move
   r25:r24=board*  r23:r22=consumer  r21:r20=context  -> r24
   Saves and restores the implicit r15:r14 (consumer) and r13:r12
   (context) registers, then installs the supplied values for the
   duration so emit_legal_move can read them via icall.
   Saved: r16,r15,r14,r13,r12,r11,r10,r9,r8
     r11:r10=board  r9=square  r8=side
   ================================================================ */
.global for_each_legal_move
.type   for_each_legal_move, @function
for_each_legal_move:
    push  r16
    push  r15
    push  r14
    push  r13
    push  r12
    push  r11
    push  r10
    push  r9
    push  r8

    movw  r14, r22           /* r15:r14 = consumer */
    movw  r12, r20           /* r13:r12 = context  */
    movw  r10, r24           /* r11:r10 = board*   */

    movw  r26, r10
    ldi   r24, BOFF_SIDE
    add   r26, r24
    adc   r27, r1
    ld    r8,  X
    clr   r9                 /* square = 0 */

felm_lp:
    ldi   r25, 64
    cp    r9,  r25
    brne  .+4
    rjmp  felm_done

    movw  r26, r10
    add   r26, r9
    adc   r27, r1
    ld    r24, X             /* piece */

    tst   r24
    brne  .+4
    rjmp  felm_nx
    mov   r25, r24
    andi  r25, CHESS_BLACK
    cp    r25, r8
    breq  .+4
    rjmp  felm_nx

    andi  r24, 0x07          /* piece type */

    cpi   r24, PIECE_PAWN
    brne  felm_kn
    movw  r24, r10
    mov   r22, r9
    rcall generate_pawn_moves
    tst   r24
    brne  .+4
    rjmp  felm_stop
    rjmp  felm_nx

felm_kn:
    cpi   r24, PIECE_KNIGHT
    brne  felm_bi
    movw  r24, r10
    mov   r22, r9
    ldi   r20, lo8(knight_df)
    ldi   r21, hi8(knight_df)
    ldi   r18, lo8(knight_dr)
    ldi   r19, hi8(knight_dr)
    ldi   r16, 8
    rcall generate_jump_moves
    tst   r24
    brne  .+4
    rjmp  felm_stop
    rjmp  felm_nx

felm_bi:
    cpi   r24, PIECE_BISHOP
    brne  felm_ro
    movw  r24, r10
    mov   r22, r9
    ldi   r20, lo8(bishop_df)
    ldi   r21, hi8(bishop_df)
    ldi   r18, lo8(bishop_dr)
    ldi   r19, hi8(bishop_dr)
    ldi   r16, 4
    rcall generate_slider_moves
    tst   r24
    breq  felm_stop
    rjmp  felm_nx

felm_ro:
    cpi   r24, PIECE_ROOK
    brne  felm_q
    movw  r24, r10
    mov   r22, r9
    ldi   r20, lo8(rook_df)
    ldi   r21, hi8(rook_df)
    ldi   r18, lo8(rook_dr)
    ldi   r19, hi8(rook_dr)
    ldi   r16, 4
    rcall generate_slider_moves
    tst   r24
    breq  felm_stop
    rjmp  felm_nx

felm_q:
    cpi   r24, PIECE_QUEEN
    brne  felm_kg
    movw  r24, r10
    mov   r22, r9
    ldi   r20, lo8(bishop_df)
    ldi   r21, hi8(bishop_df)
    ldi   r18, lo8(bishop_dr)
    ldi   r19, hi8(bishop_dr)
    ldi   r16, 4
    rcall generate_slider_moves
    tst   r24
    breq  felm_stop
    movw  r24, r10
    mov   r22, r9
    ldi   r20, lo8(rook_df)
    ldi   r21, hi8(rook_df)
    ldi   r18, lo8(rook_dr)
    ldi   r19, hi8(rook_dr)
    ldi   r16, 4
    rcall generate_slider_moves
    tst   r24
    breq  felm_stop
    rjmp  felm_nx

felm_kg:
    cpi   r24, PIECE_KING
    brne  felm_nx
    movw  r24, r10
    mov   r22, r9
    ldi   r20, lo8(king_df)
    ldi   r21, hi8(king_df)
    ldi   r18, lo8(king_dr)
    ldi   r19, hi8(king_dr)
    ldi   r16, 8
    rcall generate_jump_moves
    tst   r24
    breq  felm_stop
    movw  r24, r10
    mov   r22, r9
    rcall generate_castling
    tst   r24
    breq  felm_stop

felm_nx:
    inc   r9
    rjmp  felm_lp

felm_done:
    ldi   r24, 1
    rjmp  felm_ret
felm_stop:
    clr   r24
felm_ret:
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    pop   r12
    pop   r13
    pop   r14
    pop   r15
    pop   r16
    ret
.size for_each_legal_move, .-for_each_legal_move
