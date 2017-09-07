#!/bin/bash

# Some builds include a utility rom at A000
UTIL=pcharme_v1.73.rom

# Build the minimal image boot_c000_ffff that is just the roms (excluding SDDOS)
DIR=boot_c000_ffff
mkdir -p $DIR
cat abasic.rom afloat.rom zero akernel.rom > $DIR/atom_roms.bin
(cd $DIR; xxd -i atom_roms.bin > atom_roms.h)

# Build the minimal image boot_c000_ffff_sddos that is just the roms (including SDDOS)
# This required a correctly formatted SD Card or you will see INTERFACE? on boot
# (Ctrl-Break) will get you past this
DIR=boot_c000_ffff_sddos
mkdir -p $DIR
cat abasic.rom afloat.rom SDROM_FPGA.rom akernel_patched.rom > $DIR/atom_roms.bin
(cd $DIR; xxd -i atom_roms.bin > atom_roms.h)

# Build the larger image boot_a000_ffff that is just the roms (excluding SDDOS)
DIR=boot_a000_ffff
mkdir -p $DIR
cat $UTIL zero abasic.rom afloat.rom zero akernel.rom > $DIR/atom_roms.bin
(cd $DIR; xxd -i atom_roms.bin > atom_roms.h)

# Build the larger image boot_a000_ffff_sddos that is just the roms (including SDDOS)
# This required a correctly formatted SD Card or you will see INTERFACE? on boot
# (Ctrl-Break) will get you past this
DIR=boot_a000_ffff_sddos
mkdir -p $DIR
cat $UTIL zero abasic.rom afloat.rom SDROM_FPGA.rom akernel_patched.rom > $DIR/atom_roms.bin
(cd $DIR; xxd -i atom_roms.bin > atom_roms.h)

for game in galaxbb invadbb
do

# Build the full image boot_2900_ffff that includes Galaxians and roms (excluding SDDOS)
DIR=boot_2900_ffff_$game
mkdir -p $DIR
cat $game zero zero zero zero zero zero $UTIL zero abasic.rom afloat.rom zero akernel.rom > $DIR/atom_roms.bin
(cd $DIR; xxd -i atom_roms.bin > atom_roms.h)

# Build the full image boot_2900_ffff_sddos.bin that includes Galaxians and roms (including SDDOS)
# This requires a correctly formatted SD Card or you will see INTERFACE? on boot
# (Ctrl-Break) will get you past this
DIR=boot_2900_ffff_sddos_$game
mkdir -p $DIR
cat $game zero zero zero zero zero zero $UTIL zero abasic.rom afloat.rom SDROM_FPGA.rom akernel_patched.rom > $DIR/atom_roms.bin
(cd $DIR; xxd -i atom_roms.bin > atom_roms.h)

done

# Build the larger image boot_a000_17fff that includes paged ROMs
# This required a correctly formatted SD Card or you will see INTERFACE? on boot
# (Ctrl-Break) will get you past this
DIR=boot_b000_17fff
mkdir -p $DIR
cat bran_b010.rom abasic.rom afloat_patched_b010.rom SDROM_FPGA.rom akernel_patched.rom axr1.rom pcharme_v1.73.rom atomic_windows_v1.1.rom gags_v2.3.rom pp_toolkit.rom we_rom.rom fpgautil.rom zero > $DIR/atom_roms.bin
(cd $DIR; xxd -i atom_roms.bin > atom_roms.h)

ls -l */atom_roms.h
