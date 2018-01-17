#!/bin/bash

SRCS="../src/atom.v ../src/cpu.v ../src/ALU.v ../src/mc6847.v ../src/charrom.v ../src/vid_ram.v ../src/keyboard.v ../src/ps2_intf.v ../src/bootstrap.v ../src/spi.v ../src/m6522.v ../src/sid/sid_6581.v ../src/sid/sid_coeffs.v ../src/sid/sid_components.v ../src/sid/sid_filters.v ../src/sid/sid_voice.v"

iverilog ../src/atom_tb.v $SRCS
./a.out  
gtkwave -g -a signals.gtkw dump.vcd
