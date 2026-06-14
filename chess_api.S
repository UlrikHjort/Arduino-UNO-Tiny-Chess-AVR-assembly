/***************************************************************************
--                      tiny_chess - chess_api
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
 * NEG16 macro: two's-complement negate a 16-bit value in rhi:rlo.
 *   com  rhi
 *   neg  rlo
 *   sbci rhi, 0xFF
 *
 * Proof: com rhi = ~H. neg rlo: rlo = -L mod 256, C = (L != 0).
 *   sbci ~H, 0xFF = ~H - 0xFF - C = ~H + 1 - C.
 *   If L=0: ~H+1, rlo=0 -> -(H:0) = (256-H):0 = (~H+1):0 (ok)
 *   If L!=0: ~H,   rlo=256-L -> -(H:L) = ~H:(256-L) (ok)
 */

#define CHESS_BLACK     8
#define BOFF_SIDE       64

.text

/* ================================================================
   probe_consumer  r25:r24=move  r23:r22=next*  r21:r20=ctx*  -> r24
   Stops the iteration on the very first legal move found.
   ================================================================ */
probe_consumer:
    clr   r24
    ret

/* ================================================================
   chess_has_legal_move  r25:r24=board*  -> r24 (1=has move, 0=none)
   ================================================================ */
.global chess_has_legal_move
.type   chess_has_legal_move, @function
chess_has_legal_move:
    ldi   r22, lo8(probe_consumer)
    ldi   r23, hi8(probe_consumer)
    clr   r20
    clr   r21
    call for_each_legal_move
    /* result=0 -> consumer called -> has legal move -> return 1
       result=1 -> exhausted   -> no legal moves  -> return 0  */
    ldi   r25, 1
    eor   r24, r25           /* 0->1, 1->0 */
    ret
.size chess_has_legal_move, .-chess_has_legal_move

/* ================================================================
   chess_format_move  r25:r24=buf*  r23:r22=move
   Writes "e2e4\0" into buf (5 bytes needed).
   Saved: r29,r28,r17,r16
     r17:r16 = move_hi:move_lo
   ================================================================ */
.global chess_format_move
.type   chess_format_move, @function
chess_format_move:
    push  r29
    push  r28
    push  r17
    push  r16

    movw  r28, r24           /* Y = buf */
    mov   r16, r22           /* r16 = move_lo */
    mov   r17, r23           /* r17 = move_hi */

    /* from = move_lo & 0x3F */
    mov   r24, r16
    andi  r24, 0x3F

    /* buf[0] = 'a' + (from & 7) */
    mov   r22, r24
    andi  r22, 0x07
    ldi   r18, 'a'
    add   r22, r18
    st    Y+,  r22

    /* buf[1] = '1' + (from >> 3) */
    lsr   r24
    lsr   r24
    lsr   r24
    ldi   r18, '1'
    add   r24, r18
    st    Y+,  r24

    /* to = ((move_hi & 0x0F) << 2) | (move_lo >> 6) */
    mov   r24, r17
    andi  r24, 0x0F
    lsl   r24
    lsl   r24                /* r24 = (move_hi & 0x0F) << 2 */
    mov   r25, r16
    lsr   r25
    lsr   r25
    lsr   r25
    lsr   r25
    lsr   r25
    lsr   r25                /* r25 = move_lo >> 6 */
    or    r24, r25           /* r24 = to */

    /* buf[2] = 'a' + (to & 7) */
    mov   r22, r24
    andi  r22, 0x07
    ldi   r18, 'a'
    add   r22, r18
    st    Y+,  r22

    /* buf[3] = '1' + (to >> 3) */
    lsr   r24
    lsr   r24
    lsr   r24
    ldi   r18, '1'
    add   r24, r18
    st    Y+,  r24

    st    Y,   r1            /* buf[4] = '\0' */

    pop   r16
    pop   r17
    pop   r28
    pop   r29
    ret
.size chess_format_move, .-chess_format_move

/* ================================================================
   parse_consumer  r25:r24=move  r23:r22=next*  r21:r20=ctx*  -> r24
   parse_context layout (ctx*+0..+4):
     +0: str_lo   +1: str_hi   +2: result_lo   +3: result_hi   +4: found
   Decodes move to 4 chars, compares with ctx->str char by char.
   On match: stores move in ctx, returns 0 (stop).
   Saved: r29,r28,r17,r16,r9,r8
     r9:r8=move  r29:r28(Y)=ctx*
   ================================================================ */
parse_consumer:
    push  r29
    push  r28
    push  r17
    push  r16
    push  r9
    push  r8

    mov   r8,  r24           /* r9:r8 = move */
    mov   r9,  r25
    movw  r28, r20           /* Y = ctx* */

    /* decode from = r8 & 0x3F */
    mov   r24, r8
    andi  r24, 0x3F
    mov   r16, r24
    andi  r16, 0x07          /* r16 = from_file */
    lsr   r24
    lsr   r24
    lsr   r24
    mov   r17, r24           /* r17 = from_rank */

    /* decode to = ((r9 & 0x0F) << 2) | (r8 >> 6) */
    mov   r24, r9
    andi  r24, 0x0F
    lsl   r24
    lsl   r24
    mov   r25, r8
    lsr   r25
    lsr   r25
    lsr   r25
    lsr   r25
    lsr   r25
    lsr   r25
    or    r24, r25           /* r24 = to */

    /* load str pointer into X */
    ldd   r26, Y+0
    ldd   r27, Y+1

    /* compare char 0: 'a' + from_file */
    ld    r25, X+
    ldi   r18, 'a'
    mov   r20, r16
    add   r20, r18
    cp    r20, r25
    brne  pco_miss

    /* compare char 1: '1' + from_rank */
    ld    r25, X+
    ldi   r18, '1'
    mov   r20, r17
    add   r20, r18
    cp    r20, r25
    brne  pco_miss

    /* to_file and to_rank */
    mov   r16, r24
    andi  r16, 0x07          /* to_file */
    lsr   r24
    lsr   r24
    lsr   r24
    mov   r17, r24           /* to_rank */

    /* compare char 2: 'a' + to_file */
    ld    r25, X+
    ldi   r18, 'a'
    mov   r20, r16
    add   r20, r18
    cp    r20, r25
    brne  pco_miss

    /* compare char 3: '1' + to_rank */
    ld    r25, X+
    ldi   r18, '1'
    mov   r20, r17
    add   r20, r18
    cp    r20, r25
    brne  pco_miss

    /* match: store result, set found, return 0 */
    std   Y+2, r8
    std   Y+3, r9
    ldi   r24, 1
    std   Y+4, r24
    clr   r24
    rjmp  pco_ret

pco_miss:
    ldi   r24, 1             /* continue */

pco_ret:
    pop   r8
    pop   r9
    pop   r16
    pop   r17
    pop   r28
    pop   r29
    ret

/* ================================================================
   chess_parse_move  r25:r24=board*  r23:r22=str*  -> r25:r24
   Allocates parse_context on stack (5 bytes), runs for_each_legal_move
   with parse_consumer.  Returns matched move or 0 if not found.
   Saved: r29,r28,r11,r10,r9,r8
     r11:r10=board*  r9=SPH_old  r8=SPL_old
   ================================================================ */
.global chess_parse_move
.type   chess_parse_move, @function
chess_parse_move:
    push  r29
    push  r28
    push  r11
    push  r10
    push  r9
    push  r8

    movw  r10, r24           /* board* */
    /* r22=str_lo, r23=str_hi kept until stored in ctx */

    /* allocate 5-byte parse_context */
    in    r8,  0x3D          /* r8 = SPL_old */
    in    r9,  0x3E          /* r9 = SPH_old */
    mov   r29, r9
    mov   r28, r8
    sbiw  r28, 5
    in    r0,  0x3F
    cli
    out   0x3E, r29
    out   0x3D, r28
    out   0x3F, r0
    adiw  r28, 1             /* Y = &ctx[0] */

    std   Y+0, r22           /* ctx.str_lo */
    std   Y+1, r23           /* ctx.str_hi */
    std   Y+2, r1            /* ctx.result_lo = 0 */
    std   Y+3, r1            /* ctx.result_hi = 0 */
    std   Y+4, r1            /* ctx.found = 0 */

    movw  r24, r10
    ldi   r22, lo8(parse_consumer)
    ldi   r23, hi8(parse_consumer)
    movw  r20, r28           /* &ctx */
    call for_each_legal_move

    /* read result before restoring SP */
    ldd   r24, Y+2
    ldd   r25, Y+3
    ldd   r22, Y+4           /* found */

    /* restore SP */
    mov   r29, r9
    mov   r28, r8
    in    r0,  0x3F
    cli
    out   0x3E, r29
    out   0x3D, r28
    out   0x3F, r0

    tst   r22
    brne  cpm_done
    clr   r24
    clr   r25
cpm_done:
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    pop   r28
    pop   r29
    ret
.size chess_parse_move, .-chess_parse_move

/* ================================================================
   negamax  r25:r24=board*  r22=depth  r21:r20=alpha  r19:r18=beta
   -> r25:r24 (int16 score from current player's perspective)

   search_context layout (Y+0..+5):
     +0: depth-1   +1: alpha_lo   +2: alpha_hi
     +3: beta_lo   +4: beta_hi    +5: found
   Saved: r29,r28,r11,r10,r9,r8,r7
     r11:r10=board*  r9=depth  r8=SPL_old  r7=SPH_old
   ================================================================ */
negamax:
    push  r29
    push  r28
    push  r11
    push  r10
    push  r9
    push  r8
    push  r7

    movw  r10, r24           /* board* */
    mov   r9,  r22           /* depth */

    tst   r9
    brne  ngm_inner

    /* ---- leaf node: evaluate from current player's perspective ---- */
    movw  r24, r10
    call evaluate_board     /* r25:r24 = WHITE-positive score */
    /* if BLACK to move: negate */
    movw  r26, r10
    ldi   r22, BOFF_SIDE
    add   r26, r22
    adc   r27, r1
    ld    r22, X
    cpi   r22, CHESS_BLACK
    brne  ngm_leaf_ret
    com   r25
    neg   r24
    sbci  r25, 0xFF
ngm_leaf_ret:
    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    pop   r28
    pop   r29
    ret

ngm_inner:
    /* allocate 6-byte search_context */
    in    r7,  0x3E          /* r7 = SPH_old */
    in    r8,  0x3D          /* r8 = SPL_old */
    mov   r29, r7
    mov   r28, r8
    sbiw  r28, 6
    in    r0,  0x3F
    cli
    out   0x3E, r29
    out   0x3D, r28
    out   0x3F, r0
    adiw  r28, 1             /* Y = &ctx[0] */

    /* init ctx (r22=depth, r21:r20=alpha, r19:r18=beta still valid) */
    mov   r24, r9
    dec   r24
    std   Y+0, r24           /* ctx.depth = depth - 1 */
    std   Y+1, r20           /* ctx.alpha_lo */
    std   Y+2, r21           /* ctx.alpha_hi */
    std   Y+3, r18           /* ctx.beta_lo */
    std   Y+4, r19           /* ctx.beta_hi */
    std   Y+5, r1            /* ctx.found = 0 */

    /* for_each_legal_move(board, search_consumer, &ctx) */
    movw  r24, r10
    ldi   r22, lo8(search_consumer)
    ldi   r23, hi8(search_consumer)
    movw  r20, r28           /* &ctx (r21=r29, r20=r28) */
    call for_each_legal_move

    /* read results before restoring SP (Y still = &ctx, preserved by callee) */
    ldd   r24, Y+1           /* ctx.alpha_lo */
    ldd   r25, Y+2           /* ctx.alpha_hi  -> best score */
    ldd   r22, Y+5           /* ctx.found */

    /* restore SP */
    mov   r29, r7
    mov   r28, r8
    in    r0,  0x3F
    cli
    out   0x3E, r29
    out   0x3D, r28
    out   0x3F, r0

    tst   r22
    brne  ngm_ret_score      /* found moves: return best score */

    /* no legal moves: checkmate or stalemate */
    movw  r26, r10
    ldi   r22, BOFF_SIDE
    add   r26, r22
    adc   r27, r1
    ld    r22, X             /* side_to_move */
    movw  r24, r10
    call chess_is_in_check
    tst   r24
    breq  ngm_stalemate
    ldi   r24, lo8(-10000)
    ldi   r25, hi8(-10000)
    rjmp  ngm_ret_score

ngm_stalemate:
    clr   r24
    clr   r25

ngm_ret_score:
    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    pop   r28
    pop   r29
    ret

/* ================================================================
   search_consumer  r25:r24=move  r23:r22=next*  r21:r20=ctx*  -> r24
   search_context layout:
     +0: depth-1   +1: alpha_lo   +2: alpha_hi
     +3: beta_lo   +4: beta_hi    +5: found
   Calls negamax(next, depth-1, -beta, -alpha), negates result,
   updates ctx.alpha, returns 0 on beta-cutoff.
   Saved: r29,r28,r11,r10,r9
     r11:r10=next*  r9=depth  r29:r28(Y)=ctx*
   ================================================================ */
search_consumer:
    push  r29
    push  r28
    push  r11
    push  r10
    push  r9

    mov   r10, r22           /* r11:r10 = next* */
    mov   r11, r23
    movw  r28, r20           /* Y = ctx* */

    /* ctx.found = 1 */
    ldi   r24, 1
    std   Y+5, r24

    /* load alpha and beta */
    ldd   r24, Y+1           /* r25:r24 = alpha */
    ldd   r25, Y+2
    ldd   r18, Y+3           /* r19:r18 = beta */
    ldd   r19, Y+4
    ldd   r9,  Y+0           /* r9 = depth-1 */

    /* compute -beta -> r21:r20  (alpha arg for negamax) */
    mov   r20, r18
    mov   r21, r19
    com   r21
    neg   r20
    sbci  r21, 0xFF          /* r21:r20 = -beta */

    /* compute -alpha -> r19:r18  (beta arg for negamax) */
    mov   r18, r24
    mov   r19, r25
    com   r19
    neg   r18
    sbci  r19, 0xFF          /* r19:r18 = -alpha */

    /* call negamax(next, depth-1, -beta, -alpha) */
    movw  r24, r10           /* board* = next */
    mov   r22, r9            /* depth */
    call negamax            /* r25:r24 = inner_score */

    /* score = -inner_score */
    com   r25
    neg   r24
    sbci  r25, 0xFF

    /* update ctx.alpha if score >= ctx.alpha */
    ldd   r22, Y+1
    ldd   r23, Y+2
    cp    r24, r22           /* score - alpha (signed 16-bit) */
    cpc   r25, r23
    brlt  sc_no_update
    std   Y+1, r24
    std   Y+2, r25

sc_no_update:
    /* cutoff: if updated_alpha >= beta -> return 0 */
    ldd   r24, Y+1
    ldd   r25, Y+2
    ldd   r18, Y+3
    ldd   r19, Y+4
    cp    r24, r18           /* alpha - beta */
    cpc   r25, r19
    brge  sc_stop            /* alpha >= beta: cutoff */

    ldi   r24, 1
    rjmp  sc_ret

sc_stop:
    clr   r24

sc_ret:
    pop   r9
    pop   r10
    pop   r11
    pop   r28
    pop   r29
    ret

/* ================================================================
   root_consumer  r25:r24=move  r23:r22=next*  r21:r20=ctx*  -> r24
   root_context layout (ctx*+0..+4):
     +0: depth-1   +1: best_score_lo   +2: best_score_hi
     +3: best_move_lo   +4: best_move_hi
   Full-window negamax call; always returns 1 (no cutoff at root).
   Saved: r29,r28,r11,r10,r9,r8
     r9:r8=move  r11:r10=next*  r29:r28(Y)=ctx*
   ================================================================ */
root_consumer:
    push  r29
    push  r28
    push  r11
    push  r10
    push  r9
    push  r8

    mov   r8,  r24           /* r9:r8 = move */
    mov   r9,  r25
    mov   r10, r22           /* r11:r10 = next* */
    mov   r11, r23
    movw  r28, r20           /* Y = ctx* */

    ldd   r22, Y+0           /* depth-1 */

    /* full-window search: alpha=-10001, beta=+10001 */
    movw  r24, r10
    ldi   r20, lo8(-10001)
    ldi   r21, hi8(-10001)
    ldi   r18, lo8(10001)
    ldi   r19, hi8(10001)
    call negamax            /* r25:r24 = inner_score */

    /* score = -inner_score */
    com   r25
    neg   r24
    sbci  r25, 0xFF

    /* update best if score >= best_score (keeps first best on tie) */
    ldd   r22, Y+1
    ldd   r23, Y+2
    cp    r24, r22
    cpc   r25, r23
    brlt  rc_no_update       /* score < best: skip */
    std   Y+1, r24
    std   Y+2, r25
    std   Y+3, r8
    std   Y+4, r9

rc_no_update:
    ldi   r24, 1             /* always continue at root */

    pop   r8
    pop   r9
    pop   r10
    pop   r11
    pop   r28
    pop   r29
    ret

/* ================================================================
   chess_best_move  r25:r24=board*  r22=depth  -> r25:r24 (move)
   Allocates root_context on stack (5 bytes), runs for_each_legal_move
   with root_consumer.  Returns best move found, or 0 if none.
   root_context layout (Y+0..+4):
     +0: depth-1   +1: best_score_lo   +2: best_score_hi
     +3: best_move_lo   +4: best_move_hi
   Saved: r29,r28,r11,r10,r9,r8,r7
     r11:r10=board*  r8=SPL_old  r7=SPH_old
   ================================================================ */
.global chess_best_move
.type   chess_best_move, @function
chess_best_move:
    push  r29
    push  r28
    push  r11
    push  r10
    push  r9
    push  r8
    push  r7

    movw  r10, r24
    mov   r9,  r22           /* r9 = depth */

    /* allocate 5-byte root_context */
    in    r7,  0x3E          /* SPH_old */
    in    r8,  0x3D          /* SPL_old */
    mov   r29, r7
    mov   r28, r8
    sbiw  r28, 5
    in    r0,  0x3F
    cli
    out   0x3E, r29
    out   0x3D, r28
    out   0x3F, r0
    adiw  r28, 1             /* Y = &ctx[0] */

    mov   r24, r9
    dec   r24
    std   Y+0, r24           /* ctx.depth = depth - 1 */
    ldi   r24, lo8(-10001)
    ldi   r25, hi8(-10001)
    std   Y+1, r24           /* ctx.best_score = -10001 */
    std   Y+2, r25
    std   Y+3, r1            /* ctx.best_move = 0 */
    std   Y+4, r1

    movw  r24, r10
    ldi   r22, lo8(root_consumer)
    ldi   r23, hi8(root_consumer)
    movw  r20, r28           /* &ctx */
    call for_each_legal_move

    /* read best_move before restoring SP */
    ldd   r24, Y+3
    ldd   r25, Y+4

    /* restore SP */
    mov   r29, r7
    mov   r28, r8
    in    r0,  0x3F
    cli
    out   0x3E, r29
    out   0x3D, r28
    out   0x3F, r0

    pop   r7
    pop   r8
    pop   r9
    pop   r10
    pop   r11
    pop   r28
    pop   r29
    ret
.size chess_best_move, .-chess_best_move
