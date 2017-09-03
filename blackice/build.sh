#!/bin/bash

TOP=atom
NAME=atom
PACKAGE=tq144:4k
SRCS="../src/atom.v ../src/cpu.v ../src/ALU.v ../src/rom_c000_f000.v ../src/mc6847.v ../src/charrom.v ../src/vid_ram.v ../src/keyboard.v ../src/ps2_intf.v ../src/bootstrap.v ../src/spi.v ../src/m6522.v"

yosys -q -f "verilog -Duse_sb_io" -l ${NAME}.log -p "synth_ice40 -top ${TOP} -abc2 -blif ${NAME}.blif" ${SRCS}
arachne-pnr -d 8k -P ${PACKAGE} -p blackice.pcf ${NAME}.blif -o ${NAME}.txt
icepack ${NAME}.txt ${NAME}.bin
icetime -d hx8k -P ${PACKAGE} ${NAME}.txt
truncate -s 135104 ${NAME}.bin
