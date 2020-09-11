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

#ifndef EMU816_H
#define EMU816_H

#include "mem816.h"

#include <stdlib.h>

# define TRACE(MNEM)	{ if (trace) dump(MNEM, ea); }
# define BYTES(N)		{ if (trace) bytes(N); pc += N; }
# define SHOWPC()		{ if (trace) show(); }
# define ENDL()			{ if (trace) cout << endl; }

// Defines the WDC 65C816 emulator. 
class emu816 : public mem816
{
    public:
        emu816(bool trace=false);
        ~emu816();

        void reset(bool trace=false);
        void step();
        void run();

        inline unsigned long getCycles() { return (cycles); }
        inline bool          isStopped() { return (stopped); }

    private:
        union FLAGS {
            struct {
                Bit				f_c : 1;
                Bit				f_z : 1;
                Bit				f_i : 1;
                Bit				f_d : 1;
                Bit				f_x : 1;
                Bit				f_m : 1;
                Bit				f_v : 1;
                Bit				f_n : 1;
            };
            Byte			b;
        }   p;

        Bit		e;

        union REGS {
            Byte			b;
            Word			w;
        }   a, x, y, sp, dp;

        Word		    pc;
        Byte		    pbr, dbr;

        bool		    stopped;
        bool		    interrupted;
        unsigned long   cycles;
        bool		    trace;

        void show();
        void bytes(unsigned int);
        void dump(const char *, Addr);


        void pushByte(Byte value);
        void pushWord(Word value);
        Byte pullByte();
        Word pullWord();
        Addr am_absl();
        Addr am_absx();
        Addr am_absy();
        Addr am_absi();
        Addr am_abxi();
        Addr am_alng();
        Addr am_alnx();
        Addr am_abil();
        Addr am_dpag();
        Addr am_dpgx();
        Addr am_dpgy();
        Addr am_dpgi();
        Addr am_dpix();
        Addr am_dpiy();
        Addr am_dpil();
        Addr am_dily();
        Addr am_impl();
        Addr am_acc();
        Addr am_immb();
        Addr am_immw();
        Addr am_immm();
        Addr am_immx();
        Addr am_lrel();
        Addr am_rela();
        Addr am_srel();
        Addr am_sriy();
        void setn(unsigned int flag);
        void setv(unsigned int flag);
        void setd(unsigned int flag);
        void seti(unsigned int flag);
        void setz(unsigned int flag);
        void setc(unsigned int flag);
        void setnz_b(Byte value);
        void setnz_w(Word value);
        void op_adc(Addr ea);
        void op_and(Addr ea);
        void op_asl(Addr ea);
        void op_asla(Addr ea);
        void op_bcc(Addr ea);
        void op_bcs(Addr ea);
        void op_beq(Addr ea);
        void op_bit(Addr ea);
        void op_biti(Addr ea);
        void op_bmi(Addr ea);
        void op_bne(Addr ea);
        void op_bpl(Addr ea);
        void op_bra(Addr ea);
        void op_brk(Addr ea);
        void op_brl(Addr ea);
        void op_bvc(Addr ea);
        void op_bvs(Addr ea);
        void op_clc(Addr ea);
        void op_cld(Addr ea);
        void op_cli(Addr ea);
        void op_clv(Addr ea);
        void op_cmp(Addr ea);
        void op_cop(Addr ea);
        void op_cpx(Addr ea);
        void op_cpy(Addr ea);
        void op_dec(Addr ea);
        void op_deca(Addr ea);
        void op_dex(Addr ea);
        void op_dey(Addr ea);
        void op_eor(Addr ea);
        void op_inc(Addr ea);
        void op_inca(Addr ea);
        void op_inx(Addr ea);
        void op_iny(Addr ea);
        void op_jmp(Addr ea);
        void op_jsl(Addr ea);
        void op_jsr(Addr ea);
        void op_lda(Addr ea);
        void op_ldx(Addr ea);
        void op_ldy(Addr ea);
        void op_lsr(Addr ea);
        void op_lsra(Addr ea);
        void op_mvn(Addr ea);
        void op_mvp(Addr ea);
        void op_nop(Addr ea);
        void op_ora(Addr ea);
        void op_pea(Addr ea);
        void op_pei(Addr ea);
        void op_per(Addr ea);
        void op_pha(Addr ea);
        void op_phb(Addr ea);
        void op_phd(Addr ea);
        void op_phk(Addr ea);
        void op_php(Addr ea);
        void op_phx(Addr ea);
        void op_phy(Addr ea);
        void op_pla(Addr ea);
        void op_plb(Addr ea);
        void op_pld(Addr ea);
        void op_plk(Addr ea);
        void op_plp(Addr ea);
        void op_plx(Addr ea);
        void op_ply(Addr ea);
        void op_rep(Addr ea);
        void op_rol(Addr ea);
        void op_rola(Addr ea);
        void op_ror(Addr ea);
        void op_rora(Addr ea);
        void op_rti(Addr ea);
        void op_rtl(Addr ea);
        void op_rts(Addr ea);
        void op_sbc(Addr ea);
        void op_sec(Addr ea);
        void op_sed(Addr ea);
        void op_sei(Addr ea);
        void op_sep(Addr ea);
        void op_sta(Addr ea);
        void op_stp(Addr ea);
        void op_stx(Addr ea);
        void op_sty(Addr ea);
        void op_stz(Addr ea);
        void op_tax(Addr ea);
        void op_tay(Addr ea);
        void op_tcd(Addr ea);
        void op_tdc(Addr ea);
        void op_tcs(Addr ea);
        void op_trb(Addr ea);
        void op_tsb(Addr ea);
        void op_tsc(Addr ea);
        void op_tsx(Addr ea);
        void op_txa(Addr ea);
        void op_txs(Addr ea);
        void op_txy(Addr ea);
        void op_tya(Addr ea);
        void op_tyx(Addr ea);
        void op_wai(Addr ea);
        void op_wdm(Addr ea);
        void op_xba(Addr ea);
        void op_xce(Addr ea);
};

#endif 

