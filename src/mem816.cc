//==============================================================================
//                                          .ooooo.     .o      .ooo   
//                                         d88'   `8. o888    .88'     
//  .ooooo.  ooo. .oo.  .oo.   oooo  oooo  Y88..  .8'  888   d88'      
// d88' `88b `888P"Y88bP"Y88b  `888  `888   `88888b.   888  d888P"Ybo. 
// 888ooo888  888   888   888   888   888  .8'  ``88b  888  Y88[   ]88 
// 888    .o  888   888   888   888   888  `8.   .88P  888  `Y88   88P 
// `Y8bod8P' o888o o888o o888o  `V88V"V8P'  `boood8'  o888o  `88bod8'  
//                                                                    
// A Portable C++ WDC 65C816 Emulator  
//------------------------------------------------------------------------------
// Copyright (C),2016 Andrew John Jacobs
// All rights reserved.
//
// This work is made available under the terms of the Creative Commons
// Attribution-NonCommercial-ShareAlike 4.0 International license. Open the
// following URL to see the details.
//
// http://creativecommons.org/licenses/by-nc-sa/4.0/
//------------------------------------------------------------------------------

#include <mem816.h>

// Never used.
mem816::mem816()
: memMask(0)
, ramSize(0)
, pRAM(NULL)
, pROM(NULL)
{ 
}

// Never used.
mem816::~mem816()
{ 
    if ( pRAM )
        delete pRAM;
}

// Sets up the memory areas using a dynamically allocated array
void mem816::setMemory(Addr memMask, Addr ramSize, const Byte *pROM)
{
	setMemory(memMask, ramSize, new Byte[ramSize], pROM);
}

// Sets up the memory area using pre-allocated array
void mem816::setMemory(Addr memMask, Addr ramSize, Byte *pRAM, const Byte *pROM)
{
	mem816::memMask = memMask;
	mem816::ramSize = ramSize;
	mem816::pRAM = pRAM;
	mem816::pROM = pROM;
}

// Fetch a byte from memory
wdc816::Byte mem816::getByte(Addr ea)
{
    if ((ea &= memMask) < ramSize)
        return (pRAM[ea]);

    return (pROM[ea - ramSize]);
}

// Fetch a word from memory
wdc816::Word mem816::getWord(Addr ea)
{
        return (join(getByte(ea + 0), getByte(ea + 1)));
}

// Fetch a long address from memory
wdc816::Addr mem816::getAddr(Addr ea)
{
    return (join(getByte(ea + 2), getWord(ea + 0)));
}

// Write a byte to memory
void mem816::setByte(Addr ea, Byte data)
{
    if ((ea &= memMask) < ramSize)
        pRAM[ea] = data;
}

// Write a word to memory
void mem816::setWord(Addr ea, Word data)
{
        setByte(ea + 0, lo(data));
        setByte(ea + 1, hi(data));
}
