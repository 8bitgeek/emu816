/****************************************************************************
 * Copyright (c) 2020 Mike Sharkey <mike@pikeaero.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a 
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense, 
 * and/or sell copies of the Software, and to permit persons to whom the 
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
 * DEALINGS IN THE SOFTWARE.
 ****************************************************************************/
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
