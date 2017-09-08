#!/bin/bash

echo Assembling
ca65 -l bran.lst -o bran.o bran.asm

echo Linking
ld65 bran.o -o bran.rom -C bran.lkr

rm -f *.o

