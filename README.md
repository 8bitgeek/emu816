# emu816 - A C++ based 65C816 Emulator Library

Forked from https://github.com/andrew-jacobs/emu816

The repository contains the source code for a simple 65C816 emulator for *nix 
and CARIBOU RTOS.

## Building the library (*nix)

$ cd src
$ make

## Building the test app (*nix)

$ cd test
$ make

## Running the test app (*nix)

$ ./emu816 simple.s28

## Implementing application memory model

The following virtual methods are provided for application memory and I/O mapping.

{
        
        // FIXME - emu816 lib should not know about ROM/RAM and size.
        //         let's refactor this         
        virtual void setMemory (Addr memMask, Addr ramSize, const Byte *pROM);
        virtual void setMemory (Addr memMask, Addr ramSize, Byte *pRAM, const Byte *pROM);

        virtual Byte getByte(Addr ea);
        virtual Word getWord(Addr ea);
        virtual Addr getAddr(Addr ea);
        virtual void setByte(Addr ea, Byte data);
        virtual void setWord(Addr ea, Word data);
}