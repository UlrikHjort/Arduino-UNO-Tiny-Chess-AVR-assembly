MCU      = atmega328p
F_CPU    = 16000000UL
CC       = avr-gcc
OBJCOPY  = avr-objcopy
SIZE     = avr-size

ASFLAGS  = -mmcu=$(MCU) -DF_CPU=$(F_CPU) -x assembler-with-cpp

SRCS     = fast_math.S      \
           fast_attack.S    \
           uart.S           \
           chess_board.S    \
           chess_gen.S      \
           chess_api.S      \
           main.S

OBJS     = $(SRCS:.S=.o)
TARGET   = tiny_chess

.PHONY: all clean flash size

all: $(TARGET).hex

%.o: %.S
	$(CC) $(ASFLAGS) -c -o $@ $<

$(TARGET).elf: $(OBJS)
	$(CC) -mmcu=$(MCU) -o $@ $^

$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex -R .eeprom $< $@
	@echo "Build complete:"
	$(SIZE) --format=avr --mcu=$(MCU) $<

size: $(TARGET).elf
	$(SIZE) --format=avr --mcu=$(MCU) $<

flash: $(TARGET).hex
	avrdude -p $(MCU) -c arduino -P /dev/ttyACM1 -b 115200 -U flash:w:$<:i

clean:
	rm -f $(OBJS) $(TARGET).elf $(TARGET).hex
