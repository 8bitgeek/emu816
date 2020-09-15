#include <dbg816.h>
#include <stdio.h>
#include <string>

using namespace std;

#define inherited vm816

dbg816::dbg816()
{ 
    home();
    clear();
}

dbg816::~dbg816()
{ 
}

void dbg816::step()
{
    dump();
    inherited::step();
}

void dbg816::dump()
{
    home();
    printf( "CK:%08X:\n", cycles() );
    printf( "F:%c%c%c%c%c%c%c%c\n",
            p.f_n ? 'N' : ' ',
            p.f_v ? 'V' : ' ',
            p.f_m ? 'M' : ' ',
            p.f_x ? 'X' : ' ',
            p.f_d ? 'D' : ' ',
            p.f_i ? 'I' : ' ',
            p.f_z ? 'Z' : ' ',
            p.f_c ? 'C' : ' '
            );
    printf( "PC:%02X:%04X OP:%02X\n", pbr, pc,  inherited::load8(join(pbr, pc++)) );
    printf( "SP:%02X:%04X  D:%02X\n", 0, sp.w, inherited::load8(sp.w) );
    printf( "DR:%02X:%04X\n", 0, dp.w );
    printf( " Y:%02X:%04X\n", dbr, y.w );
    printf( " X:%02X:%04X\n", dbr, x.w );
}

void dbg816::csi()
{
    printf("%c[",0x1B);
}

void dbg816::home()
{
    csi();
    printf("1;1H");
}

void dbg816::clear()
{
    csi();
    putchar('J');
}

void dbg816::move(uint8_t x, uint8_t y)
{
    x+=1;
    y+=1;
    csi();
    printf("%d;%dH",y,x);
}


uint8_t dbg816::load8(emu816_addr_t ea)
{
    uint8_t data = inherited::load8(ea);
    move(0,7);
    printf( "RD:%02X:%04X  D:%02X\n",ea>>16,ea&0xFFFF,data );
    return data;
}

void dbg816::store8(emu816_addr_t ea, uint8_t data)
{
    move(0,8);
    printf( "WR:%02X:%04X  D:%02X\n",ea>>16,ea&0xFFFF,data );
    inherited::store8(ea,data);
}


