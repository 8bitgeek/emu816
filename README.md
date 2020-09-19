# libemu816 - A C++ based 65C816 Emulator Library

Forked from https://github.com/andrew-jacobs/emu816

## Compiling

Prerequisies:

* GCC

```
git clone https://github.com/8bitgeek/libemu816.git
cd libemu816
make
```

## Implementing application memory model

Refer to "run816" for usage example: https://github.com/8bitgeek/run816

The application memory map may be accomplished by overloading the following virtual methods.

```C++
        virtual uint8_t         load8(emu816_addr_t ea);
        virtual void            store8(emu816_addr_t ea, uint8_t data);

        virtual uint16_t        load16(emu816_addr_t ea);
        virtual void            store16(emu816_addr_t ea, uint16_t data);

        virtual emu816_addr_t   load24(emu816_addr_t ea);
```
