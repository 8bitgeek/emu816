# libemu816 - A C++ based 65C816 Emulator Library

Forked from https://github.com/andrew-jacobs/emu816

## Compiling

```
git clone https://github.com/8bitgeek/libs19.git
git submodule update --init --recursive
git pull --recurse-submodules
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
        virtual uint8_t         load8(emu816_addr_t ea);
        virtual void            store8(emu816_addr_t ea, uint8_t data);

        virtual uint16_t        load16(emu816_addr_t ea);
        virtual void            store16(emu816_addr_t ea, uint16_t data);

        virtual emu816_addr_t   load24(emu816_addr_t ea);
```
