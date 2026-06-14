# Tiny Uno Chess - Full ASM

Complete rewrite of [Arduino UNO Tiny Chess](https://github.com/UlrikHjort/Arduino-UNO-Tiny-Chess) entirely in hand-written **AVR assembly** for the **ATmega328P** (Arduino Uno). No C source files - every module is a `.S` file assembled directly with `avr-gcc`.

## What it does

- Legal move generation including castling and en passant
- Promotion input like `e7e8q`
- Shallow built-in negamax engine for the black side
- Plain text board output over serial
- Automatic new game after checkmate or stalemate

The engine is intentionally tiny and memory-first. It uses a simple material + positional evaluation with a shallow negamax search, so it is playable but not strong.

## Memory footprint

| Region | Used | Available |
|--------|------|-----------|
| Flash  | 5262 bytes (16.1%) | 32 KB |
| SRAM   | 84 bytes (4.1%)    | 2 KB  |

## Module overview

| File | Contents |
|------|----------|
| `fast_math.S` | `asm_abs8` - fast absolute value |
| `fast_attack.S` | `asm_scan_ray` - sliding piece ray walk |
| `uart.S` | UART init, putc, puts, puts\_P, getc, readline |
| `chess_board.S` | Board tables, `chess_reset`, `evaluate_board`, `is_square_attacked`, `chess_is_in_check`, `chess_apply_move` |
| `chess_gen.S` | `make_move`, `emit_legal_move`, pawn/jump/slider/castling move generators, `for_each_legal_move` |
| `chess_api.S` | `chess_has_legal_move`, `chess_format_move`, `chess_parse_move`, `negamax`, `chess_best_move` |
| `main.S` | `print_board`, game loop (White = human via UART, Black = engine) |

## Build

Requires `avr-gcc` and `avr-binutils`.

```sh
make
```

Output: `tiny_chess.hex`

## Flash

```sh
make flash
```

Adjust the port in `Makefile` if needed (default `/dev/ttyACM1`):

```sh
avrdude -p atmega328p -c arduino -P /dev/ttyACM0 -b 115200 -U flash:w:tiny_chess.hex:i
```

## Playing

Open a serial terminal (e.g minicom) at **9600 baud** and reset the board. You play **White**, the engine plays **Black**.

Enter moves in coordinate notation:

```text
  a b c d e f g h
8 r n b q k b n r 8
7 p p p p p p p p 7
6 . . . . . . . . 6
5 . . . . . . . . 5
4 . . . . . . . . 4
3 . . . . . . . . 3
2 P P P P P P P P 2
1 R N B Q K B N R 1
  a b c d e f g h
White to move
> e2e4
```

Promotion: append the piece letter - `e7e8q`, `e7e8r`, `e7e8b`, `e7e8n`.

After checkmate or stalemate the game resets automatically.

## Configuration

`ENGINE_DEPTH` in `main.S` controls the search depth (default 2). Increasing it makes the engine stronger but significantly slower on a 16 MHz AVR.

## AVR assembly notes

- Calling convention: `r25:r24` first argument and return value; `r18-r27`, `r30-r31` call-clobbered; `r2-r17`, `r28-r29` call-saved; `r1` always zero.
- PROGMEM strings use `.section .progmem.data,"a",@progbits` so they stay in flash and are accessed via `lpm` - not copied to SRAM.
- Long functions use `brXX .+4 ; rjmp target` trampolines wherever a conditional branch exceeds the AVR 63-word limit. Cross-module calls use `call`/`jmp` (4-byte absolute) rather than `rcall`/`rjmp` because the linked binary exceeds the 2047-word relative range.
