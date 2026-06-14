/***************************************************************************
--                      tiny_chess - main
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

#define CHESS_WHITE   0
#define CHESS_BLACK   8
#define BOFF_SIDE     64
#define UBRR_9600     103           /* 16 MHz / 16 / 9600 - 1 */
#define ENGINE_DEPTH  2
#define LINE_BUF_LEN  10

/* -- PROGMEM strings -------------------------------------------- */
.section .progmem.data,"a",@progbits

str_banner:   .asciz "\n=== Tiny Chess ===\nYou are White\n"
str_hdr:      .asciz "  a b c d e f g h\n"
str_white:    .asciz "White to move\n"
str_black:    .asciz "Black to move\n"
str_prompt:   .asciz "> "
str_invalid:  .asciz "Illegal move, try again\n"
str_thinking: .asciz "Engine thinking...\n"
str_engine:   .asciz "Engine plays: "
str_mate:     .asciz "Checkmate!\n"
str_stale:    .asciz "Stalemate\n"
str_newgame:  .asciz "Starting new game...\n\n"

/* -- SRAM variables --------------------------------------------- */
.section .bss
board_buf:  .fill 68, 1, 0         /* chess_board_t */
line_buf:   .fill 16, 1, 0         /* input line    */

/* -- Code ------------------------------------------------------- */
.text

/* ================================================================
   print_board  r25:r24=board*
   Prints an 8x8 ASCII board to UART.
   Saved: r29,r28,r17,r16
     r29:r28(Y)=board*  r17=rank  r16=file
   ================================================================ */
print_board:
    push  r29
    push  r28
    push  r17
    push  r16

    movw  r28, r24           /* Y = board* */

    ldi   r24, lo8(str_hdr)
    ldi   r25, hi8(str_hdr)
    call uart_puts_P

    ldi   r17, 7             /* rank 7 downto 0 */

pb_rank:
    /* rank label left */
    mov   r24, r17
    ldi   r18, '1'
    add   r24, r18
    call uart_putc
    ldi   r24, ' '
    call uart_putc

    clr   r16                /* file 0..7 */
pb_file:
    /* square = rank*8 + file */
    mov   r24, r17
    lsl   r24
    lsl   r24
    lsl   r24
    add   r24, r16           /* r24 = square index */

    movw  r26, r28
    add   r26, r24
    adc   r27, r1
    ld    r24, X             /* piece */

    call chess_piece_char   /* r24 = display char */
    call uart_putc
    ldi   r24, ' '
    call uart_putc

    inc   r16
    cpi   r16, 8
    brne  pb_file

    /* rank label right + newline */
    mov   r24, r17
    ldi   r18, '1'
    add   r24, r18
    call uart_putc
    ldi   r24, '\n'
    call uart_putc

    dec   r17
    cpi   r17, 0xFF          /* underflow after rank 0 */
    brne  pb_rank

    ldi   r24, lo8(str_hdr)
    ldi   r25, hi8(str_hdr)
    call uart_puts_P

    pop   r16
    pop   r17
    pop   r28
    pop   r29
    ret

/* ================================================================
   print_turn  r25:r24=board*
   ================================================================ */
print_turn:
    movw  r26, r24
    ldi   r24, BOFF_SIDE
    add   r26, r24
    adc   r27, r1
    ld    r24, X             /* side_to_move */
    cpi   r24, CHESS_WHITE
    breq  pt_white
    ldi   r24, lo8(str_black)
    ldi   r25, hi8(str_black)
    jmp   uart_puts_P        /* tail call */
pt_white:
    ldi   r24, lo8(str_white)
    ldi   r25, hi8(str_white)
    jmp   uart_puts_P

/* ================================================================
   announce_result  r25:r24=board*
   Prints checkmate or stalemate message.
   Saved: r17,r16
     r17:r16=board*
   ================================================================ */
announce_result:
    push  r17
    push  r16

    movw  r16, r24           /* r17:r16 = board* */

    movw  r26, r24
    ldi   r24, BOFF_SIDE
    add   r26, r24
    adc   r27, r1
    ld    r22, X             /* side_to_move */

    movw  r24, r16
    call chess_is_in_check
    tst   r24
    breq  ar_stale

    ldi   r24, lo8(str_mate)
    ldi   r25, hi8(str_mate)
    call uart_puts_P
    rjmp  ar_done

ar_stale:
    ldi   r24, lo8(str_stale)
    ldi   r25, hi8(str_stale)
    call uart_puts_P

ar_done:
    pop   r16
    pop   r17
    ret

/* ================================================================
   main
   Initialises UART, resets board, runs the game loop.
   White = human (UART), Black = engine at depth ENGINE_DEPTH.
   Saved: r17,r16
     r17:r16=move (saved across format/apply calls)
   ================================================================ */
.global main
.type   main, @function
main:
    /* uart_init(UBRR_9600) */
    ldi   r24, lo8(UBRR_9600)
    ldi   r25, hi8(UBRR_9600)
    call uart_init

    ldi   r24, lo8(str_banner)
    ldi   r25, hi8(str_banner)
    call uart_puts_P

game_reset:
    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    call chess_reset

game_loop:
    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    call print_board

    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    call print_turn

    /* check for legal moves */
    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    call chess_has_legal_move
    tst   r24
    brne  .+4
    rjmp  game_over

    /* dispatch on side_to_move */
    ldi   r26, lo8(board_buf + BOFF_SIDE)
    ldi   r27, hi8(board_buf + BOFF_SIDE)
    ld    r24, X
    cpi   r24, CHESS_WHITE
    breq  human_turn
    rjmp  engine_turn

    /* ----- human turn (White) ----- */
human_prompt:
    ldi   r24, lo8(str_prompt)
    ldi   r25, hi8(str_prompt)
    call uart_puts_P

    ldi   r24, lo8(line_buf)
    ldi   r25, hi8(line_buf)
    ldi   r22, LINE_BUF_LEN
    call uart_readline

    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    ldi   r22, lo8(line_buf)
    ldi   r23, hi8(line_buf)
    call chess_parse_move

    /* move = 0 -> invalid */
    mov   r22, r24
    or    r22, r25
    breq  human_invalid

    /* apply the move */
    movw  r22, r24
    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    call chess_apply_move
    rjmp  game_loop

human_turn:
    rjmp  human_prompt

human_invalid:
    ldi   r24, lo8(str_invalid)
    ldi   r25, hi8(str_invalid)
    call uart_puts_P
    rjmp  human_prompt

    /* ----- engine turn (Black) ----- */
engine_turn:
    push  r17
    push  r16

    ldi   r24, lo8(str_thinking)
    ldi   r25, hi8(str_thinking)
    call uart_puts_P

    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    ldi   r22, ENGINE_DEPTH
    call chess_best_move    /* r25:r24 = best move */

    /* save move in r17:r16 (call-saved) */
    movw  r16, r24

    /* format and print */
    ldi   r24, lo8(str_engine)
    ldi   r25, hi8(str_engine)
    call uart_puts_P

    ldi   r24, lo8(line_buf)
    ldi   r25, hi8(line_buf)
    movw  r22, r16
    call chess_format_move

    ldi   r24, lo8(line_buf)
    ldi   r25, hi8(line_buf)
    call uart_puts

    ldi   r24, '\n'
    call uart_putc

    /* apply the engine's move */
    movw  r22, r16
    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    call chess_apply_move

    pop   r16
    pop   r17
    rjmp  game_loop

    /* ----- no legal moves: game over ----- */
game_over:
    ldi   r24, lo8(board_buf)
    ldi   r25, hi8(board_buf)
    call announce_result

    ldi   r24, lo8(str_newgame)
    ldi   r25, hi8(str_newgame)
    call uart_puts_P

    rjmp  game_reset

    /* should never reach here */
main_halt:
    rjmp  main_halt
.size main, .-main
