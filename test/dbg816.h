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

#ifndef DBG816_H
#define DBG816_H

#include <vm816.h>
#include <stdlib.h>
#include <stdint.h>

class dbg816 : public vm816
{
    public:

        dbg816();
        virtual ~dbg816();

        virtual void        step();

        virtual uint8_t     load8(emu816_addr_t ea);
        virtual void        store8(emu816_addr_t ea, uint8_t data);

    private:

        typedef struct _opcode_
        {
            const char*     op;
            uint8_t         sz;
        } opcode_t;

        void                dump();
        void                csi();
        void                home();
        void                clear();
        void                move(uint8_t x, uint8_t y);

        static opcode_t     opcode_map[];
};

#endif 

