/***************************************************************************
--                      tiny_chess - uart
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
 * Module: uart
 *
 * ATmega328P UART driver, entirely in AVR assembly.
 *
 * Register map (extended I/O, accessed via sts/lds):
 *   0x00C0  UCSR0A  - status: bit7=RXC0, bit5=UDRE0
 *   0x00C1  UCSR0B  - control: bit4=RXEN0, bit3=TXEN0
 *   0x00C2  UCSR0C  - frame: bit2=UCSZ01, bit1=UCSZ00
 *   0x00C4  UBRR0L  - baud rate low byte
 *   0x00C5  UBRR0H  - baud rate high byte
 *   0x00C6  UDR0    - data register
 *
 * Exported functions
 * ------------------
 *   void    uart_init(uint16_t ubrr)             r25:r24
 *   void    uart_putc(char c)                    r24
 *   void    uart_puts(const char *text)          r25:r24
 *   void    uart_puts_P(PGM_P text)              r25:r24
 *   char    uart_getc(void)                      -> r24
 *   uint8_t uart_readline(char *buf, uint8_t n)  r25:r24, r22 -> r24
 */

/* ------------------------------------------------------------------ */
.text

/* ------------------------------------------------------------------ */
.global uart_init
.type   uart_init, @function
/*
 * uart_init(uint16_t ubrr)
 *   r25:r24 = ubrr
 *   Sets baud rate, enables RX+TX, 8-N-1 frame format.
 */
uart_init:
    sts  0x00C5, r25        ; UBRR0H = ubrr >> 8
    sts  0x00C4, r24        ; UBRR0L = ubrr & 0xFF
    ldi  r24, 0x18          ; (1<<RXEN0)|(1<<TXEN0)
    sts  0x00C1, r24        ; UCSR0B
    ldi  r24, 0x06          ; (1<<UCSZ01)|(1<<UCSZ00)  -> 8-bit frame
    sts  0x00C2, r24        ; UCSR0C
    ret
.size uart_init, .-uart_init

/* ------------------------------------------------------------------ */
.global uart_putc
.type   uart_putc, @function
/*
 * uart_putc(char c)
 *   r24 = c
 *   Expands '\n' to "\r\n".  Blocks until UDRE0 (transmit buffer empty).
 */
uart_putc:
    cpi  r24, 0x0A          ; '\n'
    brne uart_putc_wait
    push r24
    ldi  r24, 0x0D          ; '\r'
    rcall uart_putc
    pop  r24
uart_putc_wait:
    lds  r25, 0x00C0        ; UCSR0A
    sbrs r25, 5             ; test UDRE0 (bit 5)
    rjmp uart_putc_wait
    sts  0x00C6, r24        ; UDR0 = c
    ret
.size uart_putc, .-uart_putc

/* ------------------------------------------------------------------ */
.global uart_puts
.type   uart_puts, @function
/*
 * uart_puts(const char *text)
 *   r25:r24 = text (SRAM pointer)
 *   Sends characters until NUL.
 *   Uses Y (r29:r28) to keep the pointer across uart_putc calls.
 */
uart_puts:
    push r29
    push r28
    movw r28, r24           ; Y = text
uart_puts_loop:
    ld   r24, Y+            ; r24 = *text++
    tst  r24
    breq uart_puts_done
    rcall uart_putc
    rjmp uart_puts_loop
uart_puts_done:
    pop  r28
    pop  r29
    ret
.size uart_puts, .-uart_puts

/* ------------------------------------------------------------------ */
.global uart_puts_P
.type   uart_puts_P, @function
/*
 * uart_puts_P(PGM_P text)
 *   r25:r24 = text (flash pointer)
 *   Reads with LPM until NUL.
 *   Keeps the PROGMEM pointer in Y across uart_putc calls.
 */
uart_puts_P:
    push r29
    push r28
    movw r28, r24           ; Y = flash pointer
uart_puts_P_loop:
    movw r30, r28           ; Z = Y  (lpm needs Z)
    lpm  r24, Z+            ; r24 = pgm_read_byte(text++)
    movw r28, r30           ; Y = updated Z
    tst  r24
    breq uart_puts_P_done
    rcall uart_putc
    rjmp uart_puts_P_loop
uart_puts_P_done:
    pop  r28
    pop  r29
    ret
.size uart_puts_P, .-uart_puts_P

/* ------------------------------------------------------------------ */
.global uart_getc
.type   uart_getc, @function
/*
 * char uart_getc(void) -> r24
 *   Blocks until RXC0 (receive complete), returns byte in r24.
 */
uart_getc:
    lds  r24, 0x00C0        ; UCSR0A
    sbrs r24, 7             ; test RXC0 (bit 7)
    rjmp uart_getc
    lds  r24, 0x00C6        ; r24 = UDR0
    ret
.size uart_getc, .-uart_getc

/* ------------------------------------------------------------------ */
.global uart_readline
.type   uart_readline, @function
/*
 * uint8_t uart_readline(char *buffer, uint8_t size)
 *   r25:r24 = buffer, r22 = size  -> r24 = length
 *
 * Register allocation (all call-saved so they survive uart_putc/getc):
 *   r29:r28 (Y) = current write pointer (= buffer + len)
 *   r17         = size
 *   r16         = len
 */
uart_readline:
    push r29
    push r28
    push r17
    push r16
    movw r28, r24           ; Y = buffer
    mov  r17, r22           ; r17 = size
    clr  r16                ; len = 0

    tst  r17
    brne uart_rl_loop
    clr  r24
    rjmp uart_rl_epilogue

uart_rl_loop:
    rcall uart_getc         ; c = uart_getc() -> r24

    cpi  r24, 0x0D          ; '\r'
    breq uart_rl_enter
    cpi  r24, 0x0A          ; '\n'
    breq uart_rl_enter

    cpi  r24, 0x08          ; BS
    breq uart_rl_backspace
    cpi  r24, 127           ; DEL
    breq uart_rl_backspace

    ; check buffer full: if len + 1 >= size, discard
    mov  r25, r16
    inc  r25
    cp   r25, r17
    brsh uart_rl_loop       ; len+1 >= size -> discard

    st   Y+, r24            ; buffer[len++] = c  (Y advances)
    inc  r16
    rcall uart_putc         ; echo c (still in r24)
    rjmp uart_rl_loop

uart_rl_backspace:
    tst  r16
    breq uart_rl_loop       ; len == 0, ignore
    sbiw r28, 1             ; Y-- (back up write pointer)
    dec  r16
    ldi  r24, 0x08          ; '\b'
    rcall uart_putc
    ldi  r24, ' '
    rcall uart_putc
    ldi  r24, 0x08          ; '\b'
    rcall uart_putc
    rjmp uart_rl_loop

uart_rl_enter:
    ldi  r24, 0x0A          ; '\n'
    rcall uart_putc
    st   Y, r1              ; buffer[len] = '\0'  (r1 is always 0)
    mov  r24, r16           ; return len

uart_rl_epilogue:
    pop  r16
    pop  r17
    pop  r28
    pop  r29
    ret
.size uart_readline, .-uart_readline
