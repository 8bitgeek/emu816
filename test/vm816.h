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

#ifndef VM816_H
#define VM816_H

#include <emu816.h>

class vm816 : public emu816
{
    public:

        vm816();
        virtual ~vm816();

        // Define the memory areas and sizes
        virtual void            setMemory (emu816_addr_t memMask, emu816_addr_t ramSize, const uint8_t *pROM);
        virtual void            setMemory (emu816_addr_t memMask, emu816_addr_t ramSize, uint8_t *pRAM, const uint8_t *pROM);

        virtual uint8_t         loadByte(emu816_addr_t ea);
        virtual void            storeByte(emu816_addr_t ea, uint8_t data);
        virtual uint16_t        loadWord(emu816_addr_t ea);
        virtual void            storeWord(emu816_addr_t ea, uint16_t data);
        virtual emu816_addr_t   getAddr(emu816_addr_t ea);

    private:

        emu816_addr_t		    memMask;		// The address mask pattern
        emu816_addr_t		    ramSize;		// The amount of RAM

        uint8_t*                pRAM;			// Base of RAM memory array
        const uint8_t*          pROM;			// Base of ROM memory array

};
#endif