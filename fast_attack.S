/***************************************************************************
--                      tiny_chess - fast_attack_asm
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
 * Module: fast_attack_asm
 *
 * Exported functions
 * ------------------
 *   uint8_t asm_scan_ray(const uint8_t *squares,  -- r25:r24
 *                        uint8_t  square,          -- r22
 *                        int8_t   delta,           -- r20
 *                        uint8_t  steps,           -- r18
 *                        uint8_t  attacker_side,   -- r16
 *                        uint8_t  target_a,        -- r14
 *                        uint8_t  target_b)        -- r12
 */

.text
.global asm_scan_ray
.type asm_scan_ray, @function

asm_scan_ray:
    movw r26, r24       ; X = squares pointer
    mov  r19, r22       ; r19 = current square index

1:
    tst  r18
    breq 4f             ; steps == 0 -> return 0

    add  r19, r20       ; current_square += delta
    movw r30, r26       ; Z = base
    add  r30, r19       ; Z += index
    adc  r31, r1
    ld   r21, Z         ; r21 = squares[current_square]

    tst  r21
    breq 3f             ; empty square, keep going

    mov  r22, r21
    andi r22, 0x08      ; isolate side bit
    cp   r22, r16       ; check attacker_side
    brne 4f             ; wrong side -> blocked, return 0

    andi r21, 0x07      ; isolate piece type
    cp   r21, r14
    breq 5f
    cp   r21, r12
    breq 5f
    rjmp 4f             ; right side, wrong type -> return 0

3:
    dec  r18
    rjmp 1b

4:
    clr  r24
    ret

5:
    ldi  r24, 1
    ret

.size asm_scan_ray, .-asm_scan_ray
