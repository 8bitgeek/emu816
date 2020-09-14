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
    printf( "CK:%08X: ", cycles() );
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
    printf( "PC:%02X:%04X: OP:%02X\n", pbr, pc,  loadByte(join(pbr, pc++)) );
    printf( "Y:%02X:%04X\n", dbr, y.w );
    printf( "X:%02X:%04X\n", dbr, x.w );
    printf( "DR:%02X:%04X\n", 0, dp.w );
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


