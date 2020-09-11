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

#ifndef WDC816_H
#define WDC816_H

#include <stddef.h>
#include <stdint.h>

// The wdc816 class defines common types for 8-, 16- and 24-bit data values and
// a set of common functions for manipulating them.

class wdc816
{
    public:

        // Common types for memory and register sizes
        typedef unsigned char	Bit;
        typedef unsigned char	Byte;
        typedef unsigned short	Word;
        typedef unsigned long	Addr;

        char *toHex(unsigned long value, unsigned int digits);

        Byte lo(Word value);
        Byte hi(Word value);
        Addr bank(Byte b);
        Word join(Byte l, Byte h);
        Addr join(Byte b, Word a);
        Word swap(Word value);

    protected:

        wdc816();
        virtual ~wdc816();
        
};
#endif