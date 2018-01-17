#!/bin/bash

mkdir -p releases

release=releases/ice40atom_$(date +"%Y%m%d_%H%M").zip

echo building ${release}

rm -rf build
mkdir -p build

for board in blackice blackice2
do

    echo building ${board}
    
    pushd ${board}
    ./clean.sh
    ./build.sh
    mv atom.bin ../build/atom_${board}.bin
    popd

    pushd target/blackice/iceboot
    make clean
    make raw
    cp output/iceboot.raw icebootatom_${board}.raw
    truncate -s 126976 icebootatom_${board}.raw
    cat ../../../build/atom_${board}.bin >> icebootatom_${board}.raw
    mv icebootatom_${board}.raw ../../../build    
    popd

done

pushd build
zip -qr ../${release} .
popd

unzip -l ${release}

