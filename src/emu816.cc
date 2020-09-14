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
#include <emu816.h>

emu816::emu816()
{ 
}

emu816::~emu816()
{ 
}

// Return the low byte of a word
uint8_t emu816::lo(uint16_t value)
{
    return (uint8_t)value;
}

// Return the high byte of a word
uint8_t emu816::hi(uint16_t value)
{
    return (uint8_t)(value >> 8);
}

// Convert the bank number into a address
emu816_addr_t emu816::bank(uint8_t b)
{
    return (b << 16);
}

// Combine two bytes into a word
uint16_t emu816::join(uint8_t l, uint8_t h)
{
    return (l | (h << 8));
}

// Combine a bank and an word into an address
emu816_addr_t emu816::join(uint8_t b, uint16_t a)
{
    return (bank(b) | a);
}

// Swap the high and low bytes of a word
uint16_t emu816::swap(uint16_t value)
{
    return ((value >> 8) | (value << 8));
}

// Reset the state of emulator
void emu816::reset()
{
	e = 1;
	pbr = 0x00;
	dbr = 0x00;
	dp.w = 0x0000;
	sp.w = 0x0100;
	pc = loadWord(0xfffc);
	p.b = 0x34;

	m_stopped = false;
}

void emu816::run()
{
    while (!stopped ())
		step();    
}

void emu816::stop()
{
    m_stopped = true;
}

uint32_t emu816::cycles() 
{ 
    return m_cycles; 
}

bool emu816::stopped() 
{ 
    return m_stopped; 
}

// Execute a single instruction or invoke an interrupt
void emu816::step()
{
	// Check for NMI/IRQ

	switch (loadByte (join(pbr, pc++))) {
	case 0x00:	op_brk(am_immb());	break;
	case 0x01:	op_ora(am_dpix());	break;
	case 0x02:	op_cop(am_immb());	break;
	case 0x03:	op_ora(am_srel());	break;
	case 0x04:	op_tsb(am_dpag());	break;
	case 0x05:	op_ora(am_dpag());	break;
	case 0x06:	op_asl(am_dpag());	break;
	case 0x07:	op_ora(am_dpil());	break;
	case 0x08:	op_php(am_impl());	break;
	case 0x09:	op_ora(am_immm());	break;
	case 0x0a:	op_asla(am_acc());	break;
	case 0x0b:	op_phd(am_impl());	break;
	case 0x0c:	op_tsb(am_absl());	break;
	case 0x0d:	op_ora(am_absl());	break;
	case 0x0e:	op_asl(am_absl());	break;
	case 0x0f:	op_ora(am_alng());	break;

	case 0x10:	op_bpl(am_rela());	break;
	case 0x11:	op_ora(am_dpiy());	break;
	case 0x12:	op_ora(am_dpgi());	break;
	case 0x13:	op_ora(am_sriy());	break;
	case 0x14:	op_trb(am_dpag());	break;
	case 0x15:	op_ora(am_dpgx());	break;
	case 0x16:	op_asl(am_dpgx());	break;
	case 0x17:	op_ora(am_dily());	break;
	case 0x18:	op_clc(am_impl());	break;
	case 0x19:	op_ora(am_absy());	break;
	case 0x1a:	op_inca(am_acc());	break;
	case 0x1b:	op_tcs(am_impl());	break;
	case 0x1c:	op_trb(am_absl());	break;
	case 0x1d:	op_ora(am_absx());	break;
	case 0x1e:	op_asl(am_absx());	break;
	case 0x1f:	op_ora(am_alnx());	break;

	case 0x20:	op_jsr(am_absl());	break;
	case 0x21:	op_and(am_dpix());	break;
	case 0x22:	op_jsl(am_alng());	break;
	case 0x23:	op_and(am_srel());	break;
	case 0x24:	op_bit(am_dpag());	break;
	case 0x25:  op_and(am_dpag());	break;
	case 0x26:	op_rol(am_dpag());	break;
	case 0x27:	op_and(am_dpil());	break;
	case 0x28:	op_plp(am_impl());	break;
	case 0x29:	op_and(am_immm());	break;
	case 0x2a:	op_rola(am_acc());	break;
	case 0x2b:	op_pld(am_impl());	break;
	case 0x2c:	op_bit(am_absl());	break;
	case 0x2d:  op_and(am_absl());	break;
	case 0x2e:	op_rol(am_absl());	break;
	case 0x2f:  op_and(am_alng());	break;

	case 0x30:	op_bmi(am_rela());	break;
	case 0x31: 	op_and(am_dpiy());	break;
	case 0x32: 	op_and(am_dpgi());	break;
	case 0x33: 	op_and(am_sriy());	break;
	case 0x34:	op_bit(am_dpgx());	break;
	case 0x35: 	op_and(am_dpgx());	break;
	case 0x36:	op_rol(am_dpgx());	break;
	case 0x37: 	op_and(am_dily());	break;
	case 0x38:	op_sec(am_impl());	break;
	case 0x39: 	op_and(am_absy());	break;
	case 0x3a:	op_deca(am_acc());	break;
	case 0x3b:	op_tsc(am_impl());	break;
	case 0x3c:	op_bit(am_absx());	break;
	case 0x3d: 	op_and(am_absx());	break;
	case 0x3e:	op_rol(am_absx());	break;
	case 0x3f: 	op_and(am_alnx());	break;

	case 0x40:	op_rti(am_impl());	break;
	case 0x41:	op_eor(am_dpix());	break;
	case 0x42:	op_wdm(am_immb());	break;
	case 0x43:	op_eor(am_srel());	break;
	case 0x44:	op_mvp(am_immw());	break;
	case 0x45:	op_eor(am_dpag());	break;
	case 0x46:	op_lsr(am_dpag());	break;
	case 0x47:	op_eor(am_dpil());	break;
	case 0x48:	op_pha(am_impl());	break;
	case 0x49:	op_eor(am_immm());	break;
	case 0x4a:	op_lsra(am_impl());	break;
	case 0x4b:	op_phk(am_impl());	break;
	case 0x4c:	op_jmp(am_absl());	break;
	case 0x4d:	op_eor(am_absl());	break;
	case 0x4e:	op_lsr(am_absl());	break;
	case 0x4f:	op_eor(am_alng());	break;

	case 0x50:	op_bvc(am_rela());	break;
	case 0x51:	op_eor(am_dpiy());	break;
	case 0x52:	op_eor(am_dpgi());	break;
	case 0x53:	op_eor(am_sriy());	break;
	case 0x54:	op_mvn(am_immw());	break;
	case 0x55:	op_eor(am_dpgx());	break;
	case 0x56:	op_lsr(am_dpgx());	break;
	case 0x57:	op_eor(am_dpil());	break;
	case 0x58:	op_cli(am_impl());	break;
	case 0x59:	op_eor(am_absy());	break;
	case 0x5a:	op_phy(am_impl());	break;
	case 0x5b:	op_tcd(am_impl());	break;
	case 0x5c:	op_jmp(am_alng());	break;
	case 0x5d:	op_eor(am_absx());	break;
	case 0x5e:	op_lsr(am_absx());	break;
	case 0x5f:	op_eor(am_alnx());	break;

	case 0x60:	op_rts(am_impl());	break;
	case 0x61:	op_adc(am_dpix());	break;
	case 0x62:	op_per(am_lrel());	break;
	case 0x63:	op_adc(am_srel());	break;
	case 0x64:	op_stz(am_dpag());	break;
	case 0x65:	op_adc(am_dpag());	break;
	case 0x66:	op_ror(am_dpag());	break;
	case 0x67:	op_adc(am_dpil());	break;
	case 0x68:	op_pla(am_impl());	break;
	case 0x69:	op_adc(am_immm());	break;
	case 0x6a:	op_rora(am_impl());	break;
	case 0x6b:	op_rtl(am_impl());	break;
	case 0x6c:	op_jmp(am_absi());	break;
	case 0x6d:	op_adc(am_absl());	break;
	case 0x6e:	op_ror(am_absl());	break;
	case 0x6f:	op_adc(am_alng());	break;

	case 0x70:	op_bvs(am_rela());	break;
	case 0x71:	op_adc(am_dpiy());	break;
	case 0x72:	op_adc(am_dpgi());	break;
	case 0x73:	op_adc(am_sriy());	break;
	case 0x74:	op_stz(am_dpgx());	break;
	case 0x75:	op_adc(am_dpgx());	break;
	case 0x76:	op_ror(am_dpgx());	break;
	case 0x77:	op_adc(am_dily());	break;
	case 0x78:	op_sei(am_impl());	break;
	case 0x79:	op_adc(am_absy());	break;
	case 0x7a:	op_ply(am_impl());	break;
	case 0x7b:	op_tdc(am_impl());	break;
	case 0x7c:	op_jmp(am_abxi());	break;
	case 0x7d:	op_adc(am_absx());	break;
	case 0x7e:	op_ror(am_absx());	break;
	case 0x7f:	op_adc(am_alnx());	break;

	case 0x80:	op_bra(am_rela());	break;
	case 0x81:	op_sta(am_dpix());	break;
	case 0x82:	op_brl(am_lrel());	break;
	case 0x83:	op_sta(am_srel());	break;
	case 0x84:	op_sty(am_dpag());	break;
	case 0x85:	op_sta(am_dpag());	break;
	case 0x86:	op_stx(am_dpag());	break;
	case 0x87:	op_sta(am_dpil());	break;
	case 0x88:	op_dey(am_impl());	break;
	case 0x89:	op_biti(am_immm());	break;
	case 0x8a:	op_txa(am_impl());	break;
	case 0x8b:	op_phb(am_impl());	break;
	case 0x8c:	op_sty(am_absl());	break;
	case 0x8d:	op_sta(am_absl());	break;
	case 0x8e:	op_stx(am_absl());	break;
	case 0x8f:	op_sta(am_alng());	break;

	case 0x90:	op_bcc(am_rela());	break;
	case 0x91:	op_sta(am_dpiy());	break;
	case 0x92:	op_sta(am_dpgi());	break;
	case 0x93:	op_sta(am_sriy());	break;
	case 0x94:	op_sty(am_dpgx());	break;
	case 0x95:	op_sta(am_dpgx());	break;
	case 0x96:	op_stx(am_dpgy());	break;
	case 0x97:	op_sta(am_dily());	break;
	case 0x98:	op_tya(am_impl());	break;
	case 0x99:	op_sta(am_absy());	break;
	case 0x9a:	op_txs(am_impl());	break;
	case 0x9b:	op_txy(am_impl());	break;
	case 0x9c:	op_stz(am_absl());	break;
	case 0x9d:	op_sta(am_absx());	break;
	case 0x9e:	op_stz(am_absx());	break;
	case 0x9f:	op_sta(am_alnx());	break;

	case 0xa0:	op_ldy(am_immx());	break;
	case 0xa1:	op_lda(am_dpix());	break;
	case 0xa2:	op_ldx(am_immx());	break;
	case 0xa3:	op_lda(am_srel());	break;
	case 0xa4:	op_ldy(am_dpag());	break;
	case 0xa5:	op_lda(am_dpag());	break;
	case 0xa6:	op_ldx(am_dpag());	break;
	case 0xa7:	op_lda(am_dpil());	break;
	case 0xa8:	op_tay(am_impl());	break;
	case 0xa9:	op_lda(am_immm());	break;
	case 0xaa:	op_tax(am_impl());	break;
	case 0xab:	op_plb(am_impl());	break;
	case 0xac:	op_ldy(am_absl());	break;
	case 0xad:	op_lda(am_absl());	break;
	case 0xae:	op_ldx(am_absl());	break;
	case 0xaf:	op_lda(am_alng());	break;

	case 0xb0:	op_bcs(am_rela());	break;
	case 0xb1:	op_lda(am_dpiy());	break;
	case 0xb2:	op_lda(am_dpgi());	break;
	case 0xb3:	op_lda(am_sriy());	break;
	case 0xb4:	op_ldy(am_dpgx());	break;
	case 0xb5:	op_lda(am_dpgx());	break;
	case 0xb6:	op_ldx(am_dpgy());	break;
	case 0xb7:	op_lda(am_dily());	break;
	case 0xb8:	op_clv(am_impl());	break;
	case 0xb9:	op_lda(am_absy());	break;
	case 0xba:	op_tsx(am_impl());	break;
	case 0xbb:	op_tyx(am_impl());	break;
	case 0xbc:	op_ldy(am_absx());	break;
	case 0xbd:	op_lda(am_absx());	break;
	case 0xbe:	op_ldx(am_absy());	break;
	case 0xbf:	op_lda(am_alnx());	break;

	case 0xc0:	op_cpy(am_immx());	break;
	case 0xc1:	op_cmp(am_dpix());	break;
	case 0xc2:	op_rep(am_immb());	break;
	case 0xc3:	op_cmp(am_srel());	break;
	case 0xc4:	op_cpy(am_dpag());	break;
	case 0xc5:	op_cmp(am_dpag());	break;
	case 0xc6:	op_dec(am_dpag());	break;
	case 0xc7:	op_cmp(am_dpil());	break;
	case 0xc8:	op_iny(am_impl());	break;
	case 0xc9:	op_cmp(am_immm());	break;
	case 0xca:	op_dex(am_impl());	break;
	case 0xcb:	op_wai(am_impl());	break;
	case 0xcc:	op_cpy(am_absl());	break;
	case 0xcd:	op_cmp(am_absl());	break;
	case 0xce:	op_dec(am_absl());	break;
	case 0xcf:	op_cmp(am_alng());	break;

	case 0xd0:	op_bne(am_rela());	break;
	case 0xd1:	op_cmp(am_dpiy());	break;
	case 0xd2:	op_cmp(am_dpgi());	break;
	case 0xd3:	op_cmp(am_sriy());	break;
	case 0xd4:	op_pei(am_dpag());	break;
	case 0xd5:	op_cmp(am_dpgx());	break;
	case 0xd6:	op_dec(am_dpgx());	break;
	case 0xd7:	op_cmp(am_dily());	break;
	case 0xd8:	op_cld(am_impl());	break;
	case 0xd9:	op_cmp(am_absy());	break;
	case 0xda:	op_phx(am_impl());	break;
	case 0xdb:	op_stp(am_impl());	break;
	case 0xdc:	op_jmp(am_abil());	break;
	case 0xdd:	op_cmp(am_absx());	break;
	case 0xde:	op_dec(am_absx());	break;
	case 0xdf:	op_cmp(am_alnx());	break;

	case 0xe0:	op_cpx(am_immx());	break;
	case 0xe1:	op_sbc(am_dpix());	break;
	case 0xe2:	op_sep(am_immb());	break;
	case 0xe3:	op_sbc(am_srel());	break;
	case 0xe4:	op_cpx(am_dpag());	break;
	case 0xe5:	op_sbc(am_dpag());	break;
	case 0xe6:	op_inc(am_dpag());	break;
	case 0xe7:	op_sbc(am_dpil());	break;
	case 0xe8:	op_inx(am_impl());	break;
	case 0xe9:	op_sbc(am_immm());	break;
	case 0xea:	op_nop(am_impl());	break;
	case 0xeb:	op_xba(am_impl());	break;
	case 0xec:	op_cpx(am_absl());	break;
	case 0xed:	op_sbc(am_absl());	break;
	case 0xee:	op_inc(am_absl());	break;
	case 0xef:	op_sbc(am_alng());	break;

	case 0xf0:	op_beq(am_rela());	break;
	case 0xf1:	op_sbc(am_dpiy());	break;
	case 0xf2:	op_sbc(am_dpgi());	break;
	case 0xf3:	op_sbc(am_sriy());	break;
	case 0xf4:	op_pea(am_immw());	break;
	case 0xf5:	op_sbc(am_dpgx());	break;
	case 0xf6:	op_inc(am_dpgx());	break;
	case 0xf7:	op_sbc(am_dily());	break;
	case 0xf8:	op_sed(am_impl());	break;
	case 0xf9:	op_sbc(am_absy());	break;
	case 0xfa:	op_plx(am_impl());	break;
	case 0xfb:	op_xce(am_impl());	break;
	case 0xfc:	op_jsr(am_abxi());	break;
	case 0xfd:	op_sbc(am_absx());	break;
	case 0xfe:	op_inc(am_absx());	break;
	case 0xff:	op_sbc(am_alnx());	break;
	}
}

// Push a byte on the stack
void emu816::pushByte(uint8_t value)
{
    storeByte(sp.w, value);

    if (e)
        --sp.b;
    else
        --sp.w;
}

// Push a word on the stack
void emu816::pushuint16_t(uint16_t value)
{
    pushByte(hi(value));
    pushByte(lo(value));
}

// Pull a byte from the stack
uint8_t emu816::pullByte()
{
    if (e)
        ++sp.b;
    else
        ++sp.w;

    return (loadByte(sp.w));
}

// Pull a word from the stack
uint16_t emu816::pulluint16_t()
{
    uint8_t	l = pullByte();
    uint8_t	h = pullByte();

    return (join(l, h));
}

// Absolute - a
emu816_addr_t emu816::am_absl()
{
    emu816_addr_t	ea = join (dbr, loadWord(bank(pbr) | pc));

    fetch(2);
    m_cycles += 2;
    return (ea);
}

// Absolute Indexed X - a,X
emu816_addr_t emu816::am_absx()
{
    emu816_addr_t	ea = join(dbr, loadWord(bank(pbr) | pc)) + x.w;

    fetch(2);
    m_cycles += 2;
    return (ea);
}

// Absolute Indexed Y - a,Y
emu816_addr_t emu816::am_absy()
{
    emu816_addr_t	ea = join(dbr, loadWord(bank(pbr) | pc)) + y.w;

    fetch(2);
    m_cycles += 2;
    return (ea);
}

// Absolute Indirect - (a)
emu816_addr_t emu816::am_absi()
{
    emu816_addr_t ia = join(0, loadWord(bank(pbr) | pc));

    fetch(2);
    m_cycles += 4;
    return (join(0, loadWord(ia)));
}

// Absolute Indexed Indirect - (a,X)
emu816_addr_t emu816::am_abxi()
{
    emu816_addr_t ia = join(pbr, loadWord(join(pbr, pc))) + x.w;

    fetch(2);
    m_cycles += 4;
    return (join(pbr, loadWord(ia)));
}

// Absolute Long - >a
emu816_addr_t emu816::am_alng()
{
    emu816_addr_t ea = getAddr(join(pbr, pc));

    fetch(3);
    m_cycles += 3;
    return (ea);
}

// Absolute Long Indexed - >a,X
emu816_addr_t emu816::am_alnx()
{
    emu816_addr_t ea = getAddr(join(pbr, pc)) + x.w;

    fetch(3);
    m_cycles += 3;
    return (ea);
}

// Absolute Indirect Long - [a]
emu816_addr_t emu816::am_abil()
{
    emu816_addr_t ia = bank(0) | loadWord(join(pbr, pc));

    fetch(2);
    m_cycles += 5;
    return (getAddr(ia));
}

// Direct Page - d
emu816_addr_t emu816::am_dpag()
{
    uint8_t offset = loadByte(bank(pbr) | pc);

    fetch(1);
    m_cycles += 1;
    return (bank(0) | (uint16_t)(dp.w + offset));
}

// Direct Page Indexed X - d,X
emu816_addr_t emu816::am_dpgx()
{
    uint8_t offset = loadByte(bank(pbr) | pc) + x.b;

    fetch(1);
    m_cycles += 1;
    return (bank(0) | (uint16_t)(dp.w + offset));
}

// Direct Page Indexed Y - d,Y
emu816_addr_t emu816::am_dpgy()
{
    uint8_t offset = loadByte(bank(pbr) | pc) + y.b;

    fetch(1);
    m_cycles += 1;
    return (bank(0) | (uint16_t)(dp.w + offset));
}

// Direct Page Indirect - (d)
emu816_addr_t emu816::am_dpgi()
{
    uint8_t disp = loadByte(bank(pbr) | pc);

    fetch(1);
    m_cycles += 3;
    return (bank(dbr) | loadWord(bank(0) | (uint16_t)(dp.w + disp)));
}

// Direct Page Indexed Indirect - (d,x)
emu816_addr_t emu816::am_dpix()
{
    uint8_t disp = loadByte(join(pbr, pc));

    fetch(1);
    m_cycles += 3;
    return (bank(dbr) | loadWord(bank(0) | (uint16_t)(dp.w + disp + x.w)));
}

// Direct Page Indirect Indexed - (d),Y
emu816_addr_t emu816::am_dpiy()
{
    uint8_t disp = loadByte(join(pbr, pc));

    fetch(1);
    m_cycles += 3;
    return (bank(dbr) | loadWord(bank(0) | (dp.w + disp)) + y.w);
}

// Direct Page Indirect Long - [d]
emu816_addr_t emu816::am_dpil()
{
    uint8_t disp = loadByte(join(pbr, pc));

    fetch(1);
    m_cycles += 4;
    return (getAddr(bank(0) | (uint16_t)(dp.w + disp)));
}

// Direct Page Indirect Long Indexed - [d],Y
emu816_addr_t emu816::am_dily()
{
    uint8_t disp = loadByte(join(pbr, pc));

    fetch(1);
    m_cycles += 4;
    return (getAddr(bank(0) | (uint16_t)(dp.w + disp)) + y.w);
}

// Implied/Stack
emu816_addr_t emu816::am_impl()
{
    fetch(0);
    return (0);
}

// Accumulator
emu816_addr_t emu816::am_acc()
{
    fetch(0);
    return (0);
}

// Immediate uint8_t
emu816_addr_t emu816::am_immb()
{
    emu816_addr_t ea = bank(pbr) | pc;

    fetch(1);
    m_cycles += 0;
    return (ea);
}

// Immediate uint16_t
emu816_addr_t emu816::am_immw()
{
    emu816_addr_t ea = bank(pbr) | pc;

    fetch(2);
    m_cycles += 1;
    return (ea);
}

// Immediate based on size of A/M
emu816_addr_t emu816::am_immm()
{
    emu816_addr_t ea = join (pbr, pc);
    uint32_t size = (e || p.f_m) ? 1 : 2;

    fetch(size);
    m_cycles += size - 1;
    return (ea);
}

// Immediate based on size of X/Y
emu816_addr_t emu816::am_immx()
{
    emu816_addr_t ea = join(pbr, pc);
    uint32_t size = (e || p.f_x) ? 1 : 2;

    fetch(size);
    m_cycles += size - 1;
    return (ea);
}

// Long Relative - d
emu816_addr_t emu816::am_lrel()
{
    uint16_t disp = loadWord(join(pbr, pc));

    fetch(2);
    m_cycles += 2;
    return (bank(pbr) | (uint16_t)(pc + (signed short)disp));
}

// Relative - d
emu816_addr_t emu816::am_rela()
{
    uint8_t disp = loadByte(join(pbr, pc));

    fetch(1);
    m_cycles += 1;
    return (bank(pbr) | (uint16_t)(pc + (signed char)disp));
}

// Stack Relative - d,S
emu816_addr_t emu816::am_srel()
{
    uint8_t disp = loadByte(join(pbr, pc));

    fetch(1);
    m_cycles += 1;

    if (e)
        return((bank(0) | join(sp.b + disp, hi(sp.w))));
    else
        return (bank(0) | (uint16_t)(sp.w + disp));
}

// Stack Relative Indirect Indexed Y - (d,S),Y
emu816_addr_t emu816::am_sriy()
{
    uint8_t disp = loadByte(join(pbr, pc));
    uint16_t ia;

    fetch(1);
    m_cycles += 3;

    if (e)
        ia = loadWord(join(sp.b + disp, hi(sp.w)));
    else
        ia = loadWord(bank(0) | (sp.w + disp));

    return (bank(dbr) | (uint16_t)(ia + y.w));
}

// Set the Negative flag
void emu816::setn(uint32_t flag)
{
    p.f_n = flag ? 1 : 0;
}

// Set the Overflow flag
void emu816::setv(uint32_t flag)
{
    p.f_v = flag ? 1 : 0;
}

// Set the decimal flag
void emu816::setd(uint32_t flag)
{
    p.f_d = flag ? 1 : 0;
}

// Set the Interrupt Disable flag
void emu816::seti(uint32_t flag)
{
    p.f_i = flag ? 1 : 0;
}

// Set the Zero flag
void emu816::setz(uint32_t flag)
{
    p.f_z = flag ? 1 : 0;
}

// Set the Carry flag
void emu816::setc(uint32_t flag)
{
    p.f_c = flag ? 1 : 0;
}

// Set the Negative and Zero flags from a byte value
void emu816::setnz_b(uint8_t value)
{
    setn(value & 0x80);
    setz(value == 0);
}

// Set the Negative and Zero flags from a word value
void emu816::setnz_w(uint16_t value)
{
    setn(value & 0x8000);
    setz(value == 0);
}

void emu816::op_adc(emu816_addr_t ea)
{
    if (e || p.f_m) {
        uint8_t	data = loadByte(ea);
        uint16_t	temp = a.b + data + p.f_c;
        
        if (p.f_d) {
            if ((temp & 0x0f) > 0x09) temp += 0x06;
            if ((temp & 0xf0) > 0x90) temp += 0x60;
        }

        setc(temp & 0x100);
        setv((~(a.b ^ data)) & (a.b ^ temp) & 0x80);
        setnz_b(a.b = lo(temp));
        m_cycles += 2;
    }
    else {
        uint16_t	data = loadWord(ea);
        int		temp = a.w + data + p.f_c;

        if (p.f_d) {
            if ((temp & 0x000f) > 0x0009) temp += 0x0006;
            if ((temp & 0x00f0) > 0x0090) temp += 0x0060;
            if ((temp & 0x0f00) > 0x0900) temp += 0x0600;
            if ((temp & 0xf000) > 0x9000) temp += 0x6000;
        }
        
        setc(temp & 0x10000);
        setv((~(a.w ^ data)) & (a.w ^ temp) & 0x8000);
        setnz_w(a.w = (uint16_t)temp);
        m_cycles += 2;
    }
}

void emu816::op_and(emu816_addr_t ea)
{

    if (e || p.f_m) {
        setnz_b(a.b &= loadByte(ea));
        m_cycles += 2;
    }
    else {
        setnz_w(a.w &= loadWord(ea));
        m_cycles += 3;
    }
}

void emu816::op_asl(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);

        setc(data & 0x80);
        setnz_b(data <<= 1);
        storeByte(ea, data);
        m_cycles += 4;
    }
    else {
        uint16_t data = loadWord(ea);

        setc(data & 0x8000);
        setnz_w(data <<= 1);
        storeWord(ea, data);
        m_cycles += 5;
    }
}

void emu816::op_asla(emu816_addr_t ea)
{

    if (e || p.f_m) {
        setc(a.b & 0x80);
        setnz_b(a.b <<= 1);
        storeByte(ea, a.b);
    }
    else {
        setc(a.w & 0x8000);
        setnz_w(a.w <<= 1);
        storeWord(ea, a.w);
    }
    m_cycles += 2;
}

void emu816::op_bcc(emu816_addr_t ea)
{

    if (p.f_c == 0) {
        if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
        pc = (uint16_t)ea;
        m_cycles += 3;
    }
    else
        m_cycles += 2;
}

void emu816::op_bcs(emu816_addr_t ea)
{

    if (p.f_c == 1) {
        if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
        pc = (uint16_t)ea;
        m_cycles += 3;
    }
    else
        m_cycles += 2;
}

void emu816::op_beq(emu816_addr_t ea)
{

    if (p.f_z == 1) {
        if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
        pc = (uint16_t)ea;
        m_cycles += 3;
    }
    else
        m_cycles += 2;
}

void emu816::op_bit(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);

        setz((a.b & data) == 0);
        setn(data & 0x80);
        setv(data & 0x40);
        m_cycles += 2;
    }
    else {
        uint16_t data = loadWord(ea);

        setz((a.w & data) == 0);
        setn(data & 0x8000);
        setv(data & 0x4000);

        m_cycles += 3;
    }
}

void emu816::op_biti(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);

        setz((a.b & data) == 0);
    }
    else {
        uint16_t data = loadWord(ea);

        setz((a.w & data) == 0);
    }
    m_cycles += 2;
}

void emu816::op_bmi(emu816_addr_t ea)
{

    if (p.f_n == 1) {
        if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
        pc = (uint16_t)ea;
        m_cycles += 3;
    }
    else
        m_cycles += 2;
}

void emu816::op_bne(emu816_addr_t ea)
{

    if (p.f_z == 0) {
        if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
        pc = (uint16_t)ea;
        m_cycles += 3;
    }
    else
        m_cycles += 2;
}

void emu816::op_bpl(emu816_addr_t ea)
{

    if (p.f_n == 0) {
        if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
        pc = (uint16_t)ea;
        m_cycles += 3;
    }
    else
        m_cycles += 2;
}

void emu816::op_bra(emu816_addr_t ea)
{

    if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
    pc = (uint16_t)ea;
    m_cycles += 3;
}

void emu816::op_brk(emu816_addr_t ea)
{

    if (e) {
        pushuint16_t(pc);
        pushByte(p.b | 0x10);

        p.f_i = 1;
        p.f_d = 0;
        pbr = 0;

        pc = loadWord(0xfffe);
        m_cycles += 7;
    }
    else {
        pushByte(pbr);
        pushuint16_t(pc);
        pushByte(p.b);

        p.f_i = 1;
        p.f_d = 0;
        pbr = 0;

        pc = loadWord(0xffe6);
        m_cycles += 8;
    }
}

void emu816::op_brl(emu816_addr_t ea)
{

    pc = (uint16_t)ea;
    m_cycles += 3;
}

void emu816::op_bvc(emu816_addr_t ea)
{

    if (p.f_v == 0) {
        if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
        pc = (uint16_t)ea;
        m_cycles += 3;
    }
    else
        m_cycles += 2;
}

void emu816::op_bvs(emu816_addr_t ea)
{

    if (p.f_v == 1) {
        if (e && ((pc ^ ea) & 0xff00)) ++m_cycles;
        pc = (uint16_t)ea;
        m_cycles += 3;
    }
    else
        m_cycles += 2;
}

void emu816::op_clc(emu816_addr_t ea)
{

    setc(0);
    m_cycles += 2;
}

void emu816::op_cld(emu816_addr_t ea)
{

    setd(0);
    m_cycles += 2;
}

void emu816::op_cli(emu816_addr_t ea)
{

    seti(0);
    m_cycles += 2;
}

void emu816::op_clv(emu816_addr_t ea)
{

    setv(0);
    m_cycles += 2;
}

void emu816::op_cmp(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t	data = loadByte(ea);
        uint16_t	temp = a.b - data;

        setc(temp & 0x100);
        setnz_b(lo(temp));
        m_cycles += 2;
    }
    else {
        uint16_t	data = loadWord(ea);
        emu816_addr_t	temp = a.w - data;

        setc(temp & 0x10000L);
        setnz_w((uint16_t)temp);
        m_cycles += 3;
    }
}

void emu816::op_cop(emu816_addr_t ea)
{

    if (e) {
        pushuint16_t(pc);
        pushByte(p.b);

        p.f_i = 1;
        p.f_d = 0;
        pbr = 0;

        pc = loadWord(0xfff4);
        m_cycles += 7;
    }
    else {
        pushByte(pbr);
        pushuint16_t(pc);
        pushByte(p.b);

        p.f_i = 1;
        p.f_d = 0;
        pbr = 0;

        pc = loadWord(0xffe4);
        m_cycles += 8;
    }
}

void emu816::op_cpx(emu816_addr_t ea)
{

    if (e || p.f_x) {
        uint8_t	data = loadByte(ea);
        uint16_t	temp = x.b - data;

        setc(temp & 0x100);
        setnz_b(lo(temp));
        m_cycles += 2;
    }
    else {
        uint16_t	data = loadWord(ea);
        emu816_addr_t	temp = x.w - data;

        setc(temp & 0x10000);
        setnz_w((uint16_t) temp);
        m_cycles += 3;
    }
}

void emu816::op_cpy(emu816_addr_t ea)
{

    if (e || p.f_x) {
        uint8_t	data = loadByte(ea);
        uint16_t	temp = y.b - data;

        setc(temp & 0x100);
        setnz_b(lo(temp));
        m_cycles += 2;
    }
    else {
        uint16_t	data = loadWord(ea);
        emu816_addr_t	temp = y.w - data;

        setc(temp & 0x10000);
        setnz_w((uint16_t) temp);
        m_cycles += 3;
    }
}

void emu816::op_dec(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);

        storeByte(ea, --data);
        setnz_b(data);
        m_cycles += 4;
    }
    else {
        uint16_t data = loadWord(ea);

        storeWord(ea, --data);
        setnz_w(data);
        m_cycles += 5;
    }
}

void emu816::op_deca(emu816_addr_t ea)
{

    if (e || p.f_m)
        setnz_b(--a.b);
    else
        setnz_w(--a.w);

    m_cycles += 2;
}

void emu816::op_dex(emu816_addr_t ea)
{

    if (e || p.f_x)
        setnz_b(x.b -= 1);
    else
        setnz_w(x.w -= 1);

    m_cycles += 2;
}

void emu816::op_dey(emu816_addr_t ea)
{

    if (e || p.f_x)
        setnz_b(y.b -= 1);
    else
        setnz_w(y.w -= 1);

    m_cycles += 2;
}

void emu816::op_eor(emu816_addr_t ea)
{

    if (e || p.f_m) {
        setnz_b(a.b ^= loadByte(ea));
        m_cycles += 2;
    }
    else {
        setnz_w(a.w ^= loadWord(ea));
        m_cycles += 3;
    }
}

void emu816::op_inc(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);

        storeByte(ea, ++data);
        setnz_b(data);
        m_cycles += 4;
    }
    else {
        uint16_t data = loadWord(ea);

        storeWord(ea, ++data);
        setnz_w(data);
        m_cycles += 5;
    }
}

void emu816::op_inca(emu816_addr_t ea)
{

    if (e || p.f_m)
        setnz_b(++a.b);
    else
        setnz_w(++a.w);

    m_cycles += 2;
}

void emu816::op_inx(emu816_addr_t ea)
{

    if (e || p.f_x)
        setnz_b(++x.b);
    else
        setnz_w(++x.w);

    m_cycles += 2;
}

void emu816::op_iny(emu816_addr_t ea)
{

    if (e || p.f_x)
        setnz_b(++y.b);
    else
        setnz_w(++y.w);

    m_cycles += 2;
}

void emu816::op_jmp(emu816_addr_t ea)
{

    pbr = lo(ea >> 16);
    pc = (uint16_t)ea;
    m_cycles += 1;
}

void emu816::op_jsl(emu816_addr_t ea)
{

    pushByte(pbr);
    pushuint16_t(pc - 1);

    pbr = lo(ea >> 16);
    pc = (uint16_t)ea;
    m_cycles += 5;
}

void emu816::op_jsr(emu816_addr_t ea)
{

    pushuint16_t(pc - 1);

    pc = (uint16_t)ea;
    m_cycles += 4;
}

void emu816::op_lda(emu816_addr_t ea)
{

    if (e || p.f_m) {
        setnz_b(a.b = loadByte(ea));
        m_cycles += 2;
    }
    else {
        setnz_w(a.w = loadWord(ea));
        m_cycles += 3;
    }
}

void emu816::op_ldx(emu816_addr_t ea)
{

    if (e || p.f_x) {
        setnz_b(lo(x.w = loadByte(ea)));
        m_cycles += 2;
    }
    else {
        setnz_w(x.w = loadWord(ea));
        m_cycles += 3;
    }
}

void emu816::op_ldy(emu816_addr_t ea)
{

    if (e || p.f_x) {
        setnz_b(lo(y.w = loadByte(ea)));
        m_cycles += 2;
    }
    else {
        setnz_w(y.w = loadWord(ea));
        m_cycles += 3;
    }
}

void emu816::op_lsr(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);

        setc(data & 0x01);
        setnz_b(data >>= 1);
        storeByte(ea, data);
        m_cycles += 4;
    }
    else {
        uint16_t data = loadWord(ea);

        setc(data & 0x0001);
        setnz_w(data >>= 1);
        storeWord(ea, data);
        m_cycles += 5;
    }
}

void emu816::op_lsra(emu816_addr_t ea)
{

    if (e || p.f_m) {
        setc(a.b & 0x01);
        setnz_b(a.b >>= 1);
        storeByte(ea, a.b);
    }
    else {
        setc(a.w & 0x0001);
        setnz_w(a.w >>= 1);
        storeWord(ea, a.w);
    }
    m_cycles += 2;
}

void emu816::op_mvn(emu816_addr_t ea)
{

    uint8_t src = loadByte(ea + 1);
    uint8_t dst = loadByte(ea + 0);

    storeByte(join(dbr = dst, y.w++), loadByte(join(src, x.w++)));
    if (--a.w != 0xffff) pc -= 3;
    m_cycles += 7;
}

void emu816::op_mvp(emu816_addr_t ea)
{

    uint8_t src = loadByte(ea + 1);
    uint8_t dst = loadByte(ea + 0);

    storeByte(join(dbr = dst, y.w--), loadByte(join(src, x.w--)));
    if (--a.w != 0xffff) pc -= 3;
    m_cycles += 7;
}

void emu816::op_nop(emu816_addr_t ea)
{

    m_cycles += 2;
}

void emu816::op_ora(emu816_addr_t ea)
{

    if (e || p.f_m) {
        setnz_b(a.b |= loadByte(ea));
        m_cycles += 2;
    }
    else {
        setnz_w(a.w |= loadWord(ea));
        m_cycles += 3;
    }
}

void emu816::op_pea(emu816_addr_t ea)
{

    pushuint16_t(loadWord(ea));
    m_cycles += 5;
}

void emu816::op_pei(emu816_addr_t ea)
{

    pushuint16_t(loadWord(ea));
    m_cycles += 6;
}

void emu816::op_per(emu816_addr_t ea)
{

    pushuint16_t((uint16_t) ea);
    m_cycles += 6;
}

void emu816::op_pha(emu816_addr_t ea)
{

    if (e || p.f_m) {
        pushByte(a.b);
        m_cycles += 3;
    }
    else {
        pushuint16_t(a.w);
        m_cycles += 4;
    }
}

void emu816::op_phb(emu816_addr_t ea)
{

    pushByte(dbr);
    m_cycles += 3;
}

void emu816::op_phd(emu816_addr_t ea)
{

    pushuint16_t(dp.w);
    m_cycles += 4;
}

void emu816::op_phk(emu816_addr_t ea)
{

    pushByte(pbr);
    m_cycles += 3;
}

void emu816::op_php(emu816_addr_t ea)
{

    pushByte(p.b);
    m_cycles += 3;
}

void emu816::op_phx(emu816_addr_t ea)
{

    if (e || p.f_x) {
        pushByte(x.b);
        m_cycles += 3;
    }
    else {
        pushuint16_t(x.w);
        m_cycles += 4;
    }
}

void emu816::op_phy(emu816_addr_t ea)
{

    if (e || p.f_x) {
        pushByte(y.b);
        m_cycles += 3;
    }
    else {
        pushuint16_t(y.w);
        m_cycles += 4;
    }
}

void emu816::op_pla(emu816_addr_t ea)
{

    if (e || p.f_m) {
        setnz_b(a.b = pullByte());
        m_cycles += 4;
    }
    else {
        setnz_w(a.w = pulluint16_t());
        m_cycles += 5;
    }
}

void emu816::op_plb(emu816_addr_t ea)
{

    setnz_b(dbr = pullByte());
    m_cycles += 4;
}

void emu816::op_pld(emu816_addr_t ea)
{

    setnz_w(dp.w = pulluint16_t());
    m_cycles += 5;
}

void emu816::op_plk(emu816_addr_t ea)
{

    setnz_b(dbr = pullByte());
    m_cycles += 4;
}

void emu816::op_plp(emu816_addr_t ea)
{

    if (e)
        p.b = pullByte() | 0x30;
    else {
        p.b = pullByte();

        if (p.f_x) {
            x.w = x.b;
            y.w = y.b;
        }
    }
    m_cycles += 4;
}

void emu816::op_plx(emu816_addr_t ea)
{

    if (e || p.f_x) {
        setnz_b(lo(x.w = pullByte()));
        m_cycles += 4;
    }
    else {
        setnz_w(x.w = pulluint16_t());
        m_cycles += 5;
    }
}

void emu816::op_ply(emu816_addr_t ea)
{

    if (e || p.f_x) {
        setnz_b(lo(y.w = pullByte()));
        m_cycles += 4;
    }
    else {
        setnz_w(y.w = pulluint16_t());
        m_cycles += 5;
    }
}

void emu816::op_rep(emu816_addr_t ea)
{

    p.b &= ~loadByte(ea);
    if (e) p.f_m = p.f_x = 1;
    m_cycles += 3;
}

void emu816::op_rol(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);
        uint8_t carry = p.f_c ? 0x01 : 0x00;

        setc(data & 0x80);
        setnz_b(data = (data << 1) | carry);
        storeByte(ea, data);
        m_cycles += 4;
    }
    else {
        uint16_t data = loadWord(ea);
        uint16_t carry = p.f_c ? 0x0001 : 0x0000;

        setc(data & 0x8000);
        setnz_w(data = (data << 1) | carry);
        storeWord(ea, data);
        m_cycles += 5;
    }
}

void emu816::op_rola(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t carry = p.f_c ? 0x01 : 0x00;

        setc(a.b & 0x80);
        setnz_b(a.b = (a.b << 1) | carry);
    }
    else {
        uint16_t carry = p.f_c ? 0x0001 : 0x0000;

        setc(a.w & 0x8000);
        setnz_w(a.w = (a.w << 1) | carry);
    }
    m_cycles += 2;
}

void emu816::op_ror(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);
        uint8_t carry = p.f_c ? 0x80 : 0x00;

        setc(data & 0x01);
        setnz_b(data = (data >> 1) | carry);
        storeByte(ea, data);
        m_cycles += 4;
    }
    else {
        uint16_t data = loadWord(ea);
        uint16_t carry = p.f_c ? 0x8000 : 0x0000;

        setc(data & 0x0001);
        setnz_w(data = (data >> 1) | carry);
        storeWord(ea, data);
        m_cycles += 5;
    }
}

void emu816::op_rora(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t carry = p.f_c ? 0x80 : 0x00;

        setc(a.b & 0x01);
        setnz_b(a.b = (a.b >> 1) | carry);
    }
    else {
        uint16_t carry = p.f_c ? 0x8000 : 0x0000;

        setc(a.w & 0x0001);
        setnz_w(a.w = (a.w >> 1) | carry);
    }
    m_cycles += 2;
}

void emu816::op_rti(emu816_addr_t ea)
{

    if (e) {
        p.b = pullByte();
        pc = pulluint16_t();
        m_cycles += 6;
    }
    else {
        p.b = pullByte();
        pc = pulluint16_t();
        pbr = pullByte();
        m_cycles += 7;
    }
    p.f_i = 0;
}

void emu816::op_rtl(emu816_addr_t ea)
{

    pc = pulluint16_t() + 1;
    pbr = pullByte();
    m_cycles += 6;
}

void emu816::op_rts(emu816_addr_t ea)
{

    pc = pulluint16_t() + 1;
    m_cycles += 6;
}

void emu816::op_sbc(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t	data = ~loadByte(ea);
        uint16_t	temp = a.b + data + p.f_c;
        
        if (p.f_d) {
            if ((temp & 0x0f) > 0x09) temp += 0x06;
            if ((temp & 0xf0) > 0x90) temp += 0x60;
        }

        setc(temp & 0x100);
        setv((~(a.b ^ data)) & (a.b ^ temp) & 0x80);
        setnz_b(a.b = lo(temp));
        m_cycles += 2;
    }
    else {
        uint16_t	data = ~loadWord(ea);
        int		temp = a.w + data + p.f_c;

        if (p.f_d) {
            if ((temp & 0x000f) > 0x0009) temp += 0x0006;
            if ((temp & 0x00f0) > 0x0090) temp += 0x0060;
            if ((temp & 0x0f00) > 0x0900) temp += 0x0600;
            if ((temp & 0xf000) > 0x9000) temp += 0x6000;
        }

        setc(temp & 0x10000);
        setv((~(a.w ^ data)) & (a.w ^ temp) & 0x8000);
        setnz_w(a.w = (uint16_t)temp);
        m_cycles += 3;
    }
}

void emu816::op_sec(emu816_addr_t ea)
{

    setc(1);
    m_cycles += 2;
}

void emu816::op_sed(emu816_addr_t ea)
{

    setd(1);
    m_cycles += 2;
}

void emu816::op_sei(emu816_addr_t ea)
{

    seti(1);
    m_cycles += 2;
}

void emu816::op_sep(emu816_addr_t ea)
{

    p.b |= loadByte(ea);
    if (e) p.f_m = p.f_x = 1;

    if (p.f_x) {
        x.w = x.b;
        y.w = y.b;
    }
    m_cycles += 3;
}

void emu816::op_sta(emu816_addr_t ea)
{

    if (e || p.f_m) {
        storeByte(ea, a.b);
        m_cycles += 2;
    }
    else {
        storeWord(ea, a.w);
        m_cycles += 3;
    }
}

void emu816::op_stp(emu816_addr_t ea)
{

    pc -= 1;
    m_cycles += 3;
}

void emu816::op_stx(emu816_addr_t ea)
{

    if (e || p.f_x) {
        storeByte(ea, x.b);
        m_cycles += 2;
    }
    else {
        storeWord(ea, x.w);
        m_cycles += 3;
    }
}

void emu816::op_sty(emu816_addr_t ea)
{

    if (e || p.f_x) {
        storeByte(ea, y.b);
        m_cycles += 2;
    }
    else {
        storeWord(ea, y.w);
        m_cycles += 3;
    }
}

void emu816::op_stz(emu816_addr_t ea)
{

    if (e || p.f_m) {
        storeByte(ea, 0);
        m_cycles += 2;
    }
    else {
        storeWord(ea, 0);
        m_cycles += 3;
    }
}

void emu816::op_tax(emu816_addr_t ea)
{

    if (e || p.f_x)
        setnz_b(lo(x.w = a.b));
    else
        setnz_w(x.w = a.w);

    m_cycles += 2;
}

void emu816::op_tay(emu816_addr_t ea)
{

    if (e || p.f_x)
        setnz_b(lo(y.w = a.b));
    else
        setnz_w(y.w = a.w);

    m_cycles += 2;
}

void emu816::op_tcd(emu816_addr_t ea)
{

    dp.w = a.w;
    m_cycles += 2;
}

void emu816::op_tdc(emu816_addr_t ea)
{

    if (e || p.f_m)
        setnz_b(lo(a.w = dp.w));
    else
        setnz_w(a.w = dp.w);

    m_cycles += 2;
}

void emu816::op_tcs(emu816_addr_t ea)
{

    sp.w = e ? (0x0100 | a.b) : a.w;
    m_cycles += 2;
}

void emu816::op_trb(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);

        storeByte(ea, data & ~a.b);
        setz((a.b & data) == 0);
        m_cycles += 4;
    }
    else {
        uint16_t data = loadWord(ea);

        storeWord(ea, data & ~a.w);
        setz((a.w & data) == 0);
        m_cycles += 5;
    }
}

void emu816::op_tsb(emu816_addr_t ea)
{

    if (e || p.f_m) {
        uint8_t data = loadByte(ea);

        storeByte(ea, data | a.b);
        setz((a.b & data) == 0);
        m_cycles += 4;
    }
    else {
        uint16_t data = loadWord(ea);

        storeWord(ea, data | a.w);
        setz((a.w & data) == 0);
        m_cycles += 5;
    }
}

void emu816::op_tsc(emu816_addr_t ea)
{

    if (e || p.f_m)
        setnz_b(lo(a.w = sp.w));
    else
        setnz_w(a.w = sp.w);

    m_cycles += 2;
}

void emu816::op_tsx(emu816_addr_t ea)
{

    if (e)
        setnz_b(x.b = sp.b);
    else
        setnz_w(x.w = sp.w);

    m_cycles += 2;
}

void emu816::op_txa(emu816_addr_t ea)
{

    if (e || p.f_m)
        setnz_b(a.b = x.b);
    else
        setnz_w(a.w = x.w);

    m_cycles += 2;
}

void emu816::op_txs(emu816_addr_t ea)
{

    if (e)
        sp.w = 0x0100 | x.b;
    else
        sp.w = x.w;

    m_cycles += 2;
}

void emu816::op_txy(emu816_addr_t ea)
{

    if (e || p.f_x)
        setnz_b(lo(y.w = x.w));
    else
        setnz_w(y.w = x.w);

    m_cycles += 2;
}

void emu816::op_tya(emu816_addr_t ea)
{

    if (e || p.f_m)
        setnz_b(a.b = y.b);
    else
        setnz_w(a.w = y.w);

    m_cycles += 2;
}

void emu816::op_tyx(emu816_addr_t ea)
{

    if (e || p.f_x)
        setnz_b(lo(x.w = y.w));
    else
        setnz_w(x.w = y.w);

    m_cycles += 2;
}

void emu816::op_wai(emu816_addr_t ea)
{

    pc -= 1;
    m_cycles += 3;
}

void emu816::op_wdm(emu816_addr_t ea)
{

    switch (loadByte(ea)) {
    // case 0x01:	cout << (char) a.b; break;
    // case 0x02:  cin >> a.b;         break;
    case 0xff:	m_stopped = true;   break;
    }
    m_cycles += 3;
}

void emu816::op_xba(emu816_addr_t ea)
{

    a.w = swap(a.w);
    setnz_b(a.b);
    m_cycles += 3;
}

void emu816::op_xce(emu816_addr_t ea)
{

    uint8_t	oe = e;

    e = p.f_c;
    p.f_c = oe;

    if (e) {
        p.b |= 0x30;
        sp.w = 0x0100 | sp.b;
    }
    m_cycles += 2;
}