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

#ifndef MEM816_H
#define MEM816_H

#include <wdc816.h>

// The mem816 class defines a set of standard methods for defining and accessing
// the emulated memory area.

class mem816 : public wdc816
{
    public:

        // Define the memory areas and sizes
        virtual void setMemory (Addr memMask, Addr ramSize, const Byte *pROM);
        virtual void setMemory (Addr memMask, Addr ramSize, Byte *pRAM, const Byte *pROM);

        virtual Byte getByte(Addr ea);
        virtual Word getWord(Addr ea);
        virtual Addr getAddr(Addr ea);
        virtual void setByte(Addr ea, Byte data);
        virtual void setWord(Addr ea, Word data);

    protected:

        mem816();
        virtual ~mem816();

        Addr		memMask;		// The address mask pattern
        Addr		ramSize;		// The amount of RAM

    private:

        Byte	    *pRAM;			// Base of RAM memory array
        const Byte  *pROM;			// Base of ROM memory array

};
#endif