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

#include <stdlib.h>
#include <stdint.h>

#define EMU816_INVALID_PC   0xFFFFFFFF

typedef uint32_t	    emu816_addr_t;
typedef uint8_t         emu816_bit_t;

// Defines the WDC 65C816 emulator. 
class emu816 
{
    public:

        emu816();
        virtual ~emu816();

        virtual void            reset(uint32_t entry_point=EMU816_INVALID_PC);
        virtual void            step();
        virtual void            run(uint32_t cycles=0);
        virtual void            stop();

        uint32_t                cycles();
        bool                    stopped();

        virtual uint8_t         load8(emu816_addr_t ea) = 0;
        virtual void            store8(emu816_addr_t ea, uint8_t data) = 0;

        virtual uint16_t        load16(emu816_addr_t ea) = 0;
        virtual void            store16(emu816_addr_t ea, uint16_t data) = 0;

        virtual emu816_addr_t   load24(emu816_addr_t ea) = 0;

    protected:

        union FLAGS {
            struct {
                emu816_bit_t				f_c : 1;
                emu816_bit_t				f_z : 1;
                emu816_bit_t				f_i : 1;
                emu816_bit_t				f_d : 1;
                emu816_bit_t				f_x : 1;
                emu816_bit_t				f_m : 1;
                emu816_bit_t				f_v : 1;
                emu816_bit_t				f_n : 1;
            };
            uint8_t			b;
        }   p;

        emu816_bit_t		e;

        union REGS {
            uint8_t			b;
            uint16_t		w;
        }   a, x, y, sp, dp;

        uint16_t		    pc;
        uint8_t		        pbr, dbr;

        uint8_t                 lo(uint16_t value);
        uint8_t                 hi(uint16_t value);
        emu816_addr_t           bank(uint8_t b);
        uint16_t                join(uint8_t l, uint8_t h);
        emu816_addr_t           join(uint8_t b, uint16_t a);
        uint16_t                swap(uint16_t value);

   private:

        inline void             addPC(uint32_t count) {pc+=count;}

        bool		            m_stopped;
        uint32_t                m_cycles;

        void                    pushByte(uint8_t value);
        void                    pushuint16_t(uint16_t value);
        uint8_t                 pullByte();
        uint16_t                pulluint16_t();

        emu816_addr_t am_absl();
        emu816_addr_t am_absx();
        emu816_addr_t am_absy();
        emu816_addr_t am_absi();
        emu816_addr_t am_abxi();
        emu816_addr_t am_alng();
        emu816_addr_t am_alnx();
        emu816_addr_t am_abil();
        emu816_addr_t am_dpag();
        emu816_addr_t am_dpgx();
        emu816_addr_t am_dpgy();
        emu816_addr_t am_dpgi();
        emu816_addr_t am_dpix();
        emu816_addr_t am_dpiy();
        emu816_addr_t am_dpil();
        emu816_addr_t am_dily();
        emu816_addr_t am_impl();
        emu816_addr_t am_acc();
        emu816_addr_t am_immb();
        emu816_addr_t am_immw();
        emu816_addr_t am_immm();
        emu816_addr_t am_immx();
        emu816_addr_t am_lrel();
        emu816_addr_t am_rela();
        emu816_addr_t am_srel();
        emu816_addr_t am_sriy();
        
        void setn(uint32_t flag);
        void setv(uint32_t flag);
        void setd(uint32_t flag);
        void seti(uint32_t flag);
        void setz(uint32_t flag);
        void setc(uint32_t flag);
        void setnz_b(uint8_t value);
        void setnz_w(uint16_t value);
        void op_adc(emu816_addr_t ea);
        void op_and(emu816_addr_t ea);
        void op_asl(emu816_addr_t ea);
        void op_asla(emu816_addr_t ea);
        void op_bcc(emu816_addr_t ea);
        void op_bcs(emu816_addr_t ea);
        void op_beq(emu816_addr_t ea);
        void op_bit(emu816_addr_t ea);
        void op_biti(emu816_addr_t ea);
        void op_bmi(emu816_addr_t ea);
        void op_bne(emu816_addr_t ea);
        void op_bpl(emu816_addr_t ea);
        void op_bra(emu816_addr_t ea);
        void op_brk(emu816_addr_t ea);
        void op_brl(emu816_addr_t ea);
        void op_bvc(emu816_addr_t ea);
        void op_bvs(emu816_addr_t ea);
        void op_clc(emu816_addr_t ea);
        void op_cld(emu816_addr_t ea);
        void op_cli(emu816_addr_t ea);
        void op_clv(emu816_addr_t ea);
        void op_cmp(emu816_addr_t ea);
        void op_cop(emu816_addr_t ea);
        void op_cpx(emu816_addr_t ea);
        void op_cpy(emu816_addr_t ea);
        void op_dec(emu816_addr_t ea);
        void op_deca(emu816_addr_t ea);
        void op_dex(emu816_addr_t ea);
        void op_dey(emu816_addr_t ea);
        void op_eor(emu816_addr_t ea);
        void op_inc(emu816_addr_t ea);
        void op_inca(emu816_addr_t ea);
        void op_inx(emu816_addr_t ea);
        void op_iny(emu816_addr_t ea);
        void op_jmp(emu816_addr_t ea);
        void op_jsl(emu816_addr_t ea);
        void op_jsr(emu816_addr_t ea);
        void op_lda(emu816_addr_t ea);
        void op_ldx(emu816_addr_t ea);
        void op_ldy(emu816_addr_t ea);
        void op_lsr(emu816_addr_t ea);
        void op_lsra(emu816_addr_t ea);
        void op_mvn(emu816_addr_t ea);
        void op_mvp(emu816_addr_t ea);
        void op_nop(emu816_addr_t ea);
        void op_ora(emu816_addr_t ea);
        void op_pea(emu816_addr_t ea);
        void op_pei(emu816_addr_t ea);
        void op_per(emu816_addr_t ea);
        void op_pha(emu816_addr_t ea);
        void op_phb(emu816_addr_t ea);
        void op_phd(emu816_addr_t ea);
        void op_phk(emu816_addr_t ea);
        void op_php(emu816_addr_t ea);
        void op_phx(emu816_addr_t ea);
        void op_phy(emu816_addr_t ea);
        void op_pla(emu816_addr_t ea);
        void op_plb(emu816_addr_t ea);
        void op_pld(emu816_addr_t ea);
        void op_plk(emu816_addr_t ea);
        void op_plp(emu816_addr_t ea);
        void op_plx(emu816_addr_t ea);
        void op_ply(emu816_addr_t ea);
        void op_rep(emu816_addr_t ea);
        void op_rol(emu816_addr_t ea);
        void op_rola(emu816_addr_t ea);
        void op_ror(emu816_addr_t ea);
        void op_rora(emu816_addr_t ea);
        void op_rti(emu816_addr_t ea);
        void op_rtl(emu816_addr_t ea);
        void op_rts(emu816_addr_t ea);
        void op_sbc(emu816_addr_t ea);
        void op_sec(emu816_addr_t ea);
        void op_sed(emu816_addr_t ea);
        void op_sei(emu816_addr_t ea);
        void op_sep(emu816_addr_t ea);
        void op_sta(emu816_addr_t ea);
        void op_stp(emu816_addr_t ea);
        void op_stx(emu816_addr_t ea);
        void op_sty(emu816_addr_t ea);
        void op_stz(emu816_addr_t ea);
        void op_tax(emu816_addr_t ea);
        void op_tay(emu816_addr_t ea);
        void op_tcd(emu816_addr_t ea);
        void op_tdc(emu816_addr_t ea);
        void op_tcs(emu816_addr_t ea);
        void op_trb(emu816_addr_t ea);
        void op_tsb(emu816_addr_t ea);
        void op_tsc(emu816_addr_t ea);
        void op_tsx(emu816_addr_t ea);
        void op_txa(emu816_addr_t ea);
        void op_txs(emu816_addr_t ea);
        void op_txy(emu816_addr_t ea);
        void op_tya(emu816_addr_t ea);
        void op_tyx(emu816_addr_t ea);
        void op_wai(emu816_addr_t ea);
        void op_wdm(emu816_addr_t ea);
        void op_xba(emu816_addr_t ea);
        void op_xce(emu816_addr_t ea);
};

#endif 

