# libemu816 - A C++ based 65C816 Emulator Library

Forked from https://github.com/andrew-jacobs/emu816

The objective is to develop a verifiable/verified 65c816 emulator library.

## Compiling

```
make
```

## Running a test

* NOTE: The contents of 'test' are currently transient, a place holder for verification tests.

```
cd test
./run816 simple.s28
```

## Implementing application memory model

The application memory map may be accomplished by overloading the following virtual methods.

```C++
        virtual uint8_t         loadByte(emu816_addr_t ea);
        virtual void            storeByte(emu816_addr_t ea, uint8_t data);

        virtual uint16_t        loadWord(emu816_addr_t ea);
        virtual emu816_addr_t   getAddr(emu816_addr_t ea);
        virtual void            storeWord(emu816_addr_t ea, uint16_t data);
```
