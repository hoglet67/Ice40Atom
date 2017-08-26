#!/bin/bash

SRCS="../src/atom.v ../src/cpu.v ../src/ALU.v ../src/rom_c000_f000.v ../src/mc6847.v ../src/charrom.v ../src/vid_ram.v ../src/keyboard.v ../src/ps2_intf.v"

iverilog ../src/atom_tb.v $SRCS
./a.out  
gtkwave -a signals.gtkw dump.vcd
