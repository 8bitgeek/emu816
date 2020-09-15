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

#include <vm816.h>

vm816::vm816()
: memMask(0)
, ramSize(0)
, pRAM(NULL)
, pROM(NULL)
{ 
}

vm816::~vm816()
{ 
    if ( pRAM )
        delete pRAM;
}

// Sets up the memory areas using a dynamically allocated array
void vm816::setMemory(emu816_addr_t memMask, emu816_addr_t ramSize, const uint8_t *pROM)
{
	setMemory(memMask, ramSize, new uint8_t[ramSize], pROM);
}

// Sets up the memory area using pre-allocated array
void vm816::setMemory(emu816_addr_t memMask, emu816_addr_t ramSize, uint8_t *pRAM, const uint8_t *pROM)
{
	vm816::memMask = memMask;
	vm816::ramSize = ramSize;
	vm816::pRAM = pRAM;
	vm816::pROM = pROM;
}

// Fetch a uint8_t from memory
uint8_t vm816::load8(emu816_addr_t ea)
{
    if ((ea &= memMask) < ramSize)
        return (pRAM[ea]);

    return (pROM[ea - ramSize]);
}

// Fetch a word from memory
uint16_t vm816::load16(emu816_addr_t ea)
{
        return (join(load8(ea + 0), load8(ea + 1)));
}

// Fetch a long address from memory
emu816_addr_t vm816::load24(emu816_addr_t ea)
{
    return (join(load8(ea + 2), load16(ea + 0)));
}

// Write a uint8_t to memory
void vm816::store8(emu816_addr_t ea, uint8_t data)
{
    if ((ea &= memMask) < ramSize)
        pRAM[ea] = data;
}

// Write a word to memory
void vm816::store16(emu816_addr_t ea, uint16_t data)
{
    store8(ea + 0, lo(data));
    store8(ea + 1, hi(data));
}
