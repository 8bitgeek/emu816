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
#include <iostream>
#include <string>
#include <emu816.h>

using namespace std;


//==============================================================================

// Not used.
emu816::emu816(bool trace)
{ 
}

// Not used
emu816::~emu816()
{ 
}

// Reset the state of emulator
void emu816::reset(bool trace)
{
	e = 1;
	pbr = 0x00;
	dbr = 0x00;
	dp.w = 0x0000;
	sp.w = 0x0100;
	pc = getWord(0xfffc);
	p.b = 0x34;

	stopped = false;
	interrupted = false;
	
	emu816::trace = trace;
}

void emu816::run()
{
    while (!isStopped ())
		step();    
}


// Execute a single instruction or invoke an interrupt
void emu816::step()
{
	// Check for NMI/IRQ

	SHOWPC();

	switch (getByte (join(pbr, pc++))) {
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

//==============================================================================
// Debugging Utilities
//------------------------------------------------------------------------------

// The current PC and opcode byte
void emu816::show()
{
//	cout << '{' << toHex(cycles, 4) << "} ";
	cout << toHex(pbr, 2);
	cout << ':' << toHex(pc, 4);
	cout << ' ' << toHex(getByte(join(pbr, pc)), 2);
}

// Display the operand bytes
void emu816::bytes(uint32_t count)
{
	if (count > 0)
		cout << ' ' << toHex(getByte(bank(pbr) | (pc + 0)), 2);
	else
		cout << "   ";

	if (count > 1)
		cout << ' ' << toHex(getByte(bank(pbr) | (pc + 1)), 2);
	else
		cout << "   ";

	if (count > 2)
		cout << ' ' << toHex(getByte(bank(pbr) | (pc + 2)), 2);
	else
		cout << "   ";

	cout << ' ';
}

// Display registers and top of stack
void emu816::dump(const char *mnem, Addr ea)
{
	cout << mnem << " {";
	cout << toHex(ea >> 16, 2) << ':';
	cout << toHex(ea, 4) << '}';

	cout << " E=" << toHex(e, 1);
	cout << " P=" <<
		(p.f_n ? 'N' : '.') <<
		(p.f_v ? 'V' : '.') <<
		(p.f_m ? 'M' : '.') <<
		(p.f_x ? 'X' : '.') <<
		(p.f_d ? 'D' : '.') <<
		(p.f_i ? 'I' : '.') <<
		(p.f_z ? 'Z' : '.') <<
		(p.f_c ? 'C' : '.');
	cout << " A=";
	if (e || p.f_m)
		cout << toHex(hi(a.w), 2) << '[';
	else
		cout << '[' << toHex(hi(a.w), 2);
	cout << toHex(a.b, 2) << ']';
	cout << " X=";
	if (e || p.f_x)
		cout << toHex(hi(x.w), 2) << '[';
	else
		cout << '[' << toHex(hi(x.w), 2);
	cout << toHex(x.b, 2) << ']';
	cout << " Y=";
	if (e || p.f_x)
		cout << toHex(hi(y.w), 2) << '[';
	else
		cout << '[' << toHex(hi(y.w), 2);
	cout << toHex(y.b, 2) << ']';
	cout << " DP=" << toHex(dp.w, 4);
	cout << " SP=";
	if (e)
		cout << toHex(hi(sp.w), 2) << '[';
	else
		cout << '[' << toHex(hi(sp.w), 2);
	cout << toHex(sp.b, 2) << ']';
	cout << " {";
	cout << ' ' << toHex(getByte(sp.w + 1), 2);
	cout << ' ' << toHex(getByte(sp.w + 2), 2);
	cout << ' ' << toHex(getByte(sp.w + 3), 2);
	cout << ' ' << toHex(getByte(sp.w + 4), 2);
	cout << " }";
	cout << " DBR=" << toHex(dbr, 2) << endl;
}




// Push a byte on the stack
void emu816::pushByte(Byte value)
{
    setByte(sp.w, value);

    if (e)
        --sp.b;
    else
        --sp.w;
}

// Push a word on the stack
void emu816::pushWord(Word value)
{
    pushByte(hi(value));
    pushByte(lo(value));
}

// Pull a byte from the stack
emu816::Byte emu816::pullByte()
{
    if (e)
        ++sp.b;
    else
        ++sp.w;

    return (getByte(sp.w));
}

// Pull a word from the stack
emu816::Word emu816::pullWord()
{
    register Byte	l = pullByte();
    register Byte	h = pullByte();

    return (join(l, h));
}

// Absolute - a
emu816::Addr emu816::am_absl()
{
    register Addr	ea = join (dbr, getWord(bank(pbr) | pc));

    BYTES(2);
    cycles += 2;
    return (ea);
}

// Absolute Indexed X - a,X
emu816::Addr emu816::am_absx()
{
    register Addr	ea = join(dbr, getWord(bank(pbr) | pc)) + x.w;

    BYTES(2);
    cycles += 2;
    return (ea);
}

// Absolute Indexed Y - a,Y
emu816::Addr emu816::am_absy()
{
    register Addr	ea = join(dbr, getWord(bank(pbr) | pc)) + y.w;

    BYTES(2);
    cycles += 2;
    return (ea);
}

// Absolute Indirect - (a)
emu816::Addr emu816::am_absi()
{
    register Addr ia = join(0, getWord(bank(pbr) | pc));

    BYTES(2);
    cycles += 4;
    return (join(0, getWord(ia)));
}

// Absolute Indexed Indirect - (a,X)
emu816::Addr emu816::am_abxi()
{
    register Addr ia = join(pbr, getWord(join(pbr, pc))) + x.w;

    BYTES(2);
    cycles += 4;
    return (join(pbr, getWord(ia)));
}

// Absolute Long - >a
emu816::Addr emu816::am_alng()
{
    Addr ea = getAddr(join(pbr, pc));

    BYTES(3);
    cycles += 3;
    return (ea);
}

// Absolute Long Indexed - >a,X
emu816::Addr emu816::am_alnx()
{
    register Addr ea = getAddr(join(pbr, pc)) + x.w;

    BYTES(3);
    cycles += 3;
    return (ea);
}

// Absolute Indirect Long - [a]
emu816::Addr emu816::am_abil()
{
    register Addr ia = bank(0) | getWord(join(pbr, pc));

    BYTES(2);
    cycles += 5;
    return (getAddr(ia));
}

// Direct Page - d
emu816::Addr emu816::am_dpag()
{
    Byte offset = getByte(bank(pbr) | pc);

    BYTES(1);
    cycles += 1;
    return (bank(0) | (Word)(dp.w + offset));
}

// Direct Page Indexed X - d,X
emu816::Addr emu816::am_dpgx()
{
    Byte offset = getByte(bank(pbr) | pc) + x.b;

    BYTES(1);
    cycles += 1;
    return (bank(0) | (Word)(dp.w + offset));
}

// Direct Page Indexed Y - d,Y
emu816::Addr emu816::am_dpgy()
{
    Byte offset = getByte(bank(pbr) | pc) + y.b;

    BYTES(1);
    cycles += 1;
    return (bank(0) | (Word)(dp.w + offset));
}

// Direct Page Indirect - (d)
emu816::Addr emu816::am_dpgi()
{
    Byte disp = getByte(bank(pbr) | pc);

    BYTES(1);
    cycles += 3;
    return (bank(dbr) | getWord(bank(0) | (Word)(dp.w + disp)));
}

// Direct Page Indexed Indirect - (d,x)
emu816::Addr emu816::am_dpix()
{
    Byte disp = getByte(join(pbr, pc));

    BYTES(1);
    cycles += 3;
    return (bank(dbr) | getWord(bank(0) | (Word)(dp.w + disp + x.w)));
}

// Direct Page Indirect Indexed - (d),Y
emu816::Addr emu816::am_dpiy()
{
    Byte disp = getByte(join(pbr, pc));

    BYTES(1);
    cycles += 3;
    return (bank(dbr) | getWord(bank(0) | (dp.w + disp)) + y.w);
}

// Direct Page Indirect Long - [d]
emu816::Addr emu816::am_dpil()
{
    Byte disp = getByte(join(pbr, pc));

    BYTES(1);
    cycles += 4;
    return (getAddr(bank(0) | (Word)(dp.w + disp)));
}

// Direct Page Indirect Long Indexed - [d],Y
emu816::Addr emu816::am_dily()
{
    Byte disp = getByte(join(pbr, pc));

    BYTES(1);
    cycles += 4;
    return (getAddr(bank(0) | (Word)(dp.w + disp)) + y.w);
}

// Implied/Stack
emu816::Addr emu816::am_impl()
{
    BYTES(0);
    return (0);
}

// Accumulator
emu816::Addr emu816::am_acc()
{
    BYTES(0);
    return (0);
}

// Immediate Byte
emu816::Addr emu816::am_immb()
{
    Addr ea = bank(pbr) | pc;

    BYTES(1);
    cycles += 0;
    return (ea);
}

// Immediate Word
emu816::Addr emu816::am_immw()
{
    Addr ea = bank(pbr) | pc;

    BYTES(2);
    cycles += 1;
    return (ea);
}

// Immediate based on size of A/M
emu816::Addr emu816::am_immm()
{
    Addr ea = join (pbr, pc);
    uint32_t size = (e || p.f_m) ? 1 : 2;

    BYTES(size);
    cycles += size - 1;
    return (ea);
}

// Immediate based on size of X/Y
emu816::Addr emu816::am_immx()
{
    Addr ea = join(pbr, pc);
    uint32_t size = (e || p.f_x) ? 1 : 2;

    BYTES(size);
    cycles += size - 1;
    return (ea);
}

// Long Relative - d
emu816::Addr emu816::am_lrel()
{
    Word disp = getWord(join(pbr, pc));

    BYTES(2);
    cycles += 2;
    return (bank(pbr) | (Word)(pc + (signed short)disp));
}

// Relative - d
emu816::Addr emu816::am_rela()
{
    Byte disp = getByte(join(pbr, pc));

    BYTES(1);
    cycles += 1;
    return (bank(pbr) | (Word)(pc + (signed char)disp));
}

// Stack Relative - d,S
emu816::Addr emu816::am_srel()
{
    Byte disp = getByte(join(pbr, pc));

    BYTES(1);
    cycles += 1;

    if (e)
        return((bank(0) | join(sp.b + disp, hi(sp.w))));
    else
        return (bank(0) | (Word)(sp.w + disp));
}

// Stack Relative Indirect Indexed Y - (d,S),Y
emu816::Addr emu816::am_sriy()
{
    Byte disp = getByte(join(pbr, pc));
    register Word ia;

    BYTES(1);
    cycles += 3;

    if (e)
        ia = getWord(join(sp.b + disp, hi(sp.w)));
    else
        ia = getWord(bank(0) | (sp.w + disp));

    return (bank(dbr) | (Word)(ia + y.w));
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
void emu816::setnz_b(Byte value)
{
    setn(value & 0x80);
    setz(value == 0);
}

// Set the Negative and Zero flags from a word value
void emu816::setnz_w(Word value)
{
    setn(value & 0x8000);
    setz(value == 0);
}

void emu816::op_adc(Addr ea)
{
    TRACE("ADC");

    if (e || p.f_m) {
        Byte	data = getByte(ea);
        Word	temp = a.b + data + p.f_c;
        
        if (p.f_d) {
            if ((temp & 0x0f) > 0x09) temp += 0x06;
            if ((temp & 0xf0) > 0x90) temp += 0x60;
        }

        setc(temp & 0x100);
        setv((~(a.b ^ data)) & (a.b ^ temp) & 0x80);
        setnz_b(a.b = lo(temp));
        cycles += 2;
    }
    else {
        Word	data = getWord(ea);
        int		temp = a.w + data + p.f_c;

        if (p.f_d) {
            if ((temp & 0x000f) > 0x0009) temp += 0x0006;
            if ((temp & 0x00f0) > 0x0090) temp += 0x0060;
            if ((temp & 0x0f00) > 0x0900) temp += 0x0600;
            if ((temp & 0xf000) > 0x9000) temp += 0x6000;
        }
        
        setc(temp & 0x10000);
        setv((~(a.w ^ data)) & (a.w ^ temp) & 0x8000);
        setnz_w(a.w = (Word)temp);
        cycles += 2;
    }
}

void emu816::op_and(Addr ea)
{
    TRACE("AND");

    if (e || p.f_m) {
        setnz_b(a.b &= getByte(ea));
        cycles += 2;
    }
    else {
        setnz_w(a.w &= getWord(ea));
        cycles += 3;
    }
}

void emu816::op_asl(Addr ea)
{
    TRACE("ASL");

    if (e || p.f_m) {
        register Byte data = getByte(ea);

        setc(data & 0x80);
        setnz_b(data <<= 1);
        setByte(ea, data);
        cycles += 4;
    }
    else {
        register Word data = getWord(ea);

        setc(data & 0x8000);
        setnz_w(data <<= 1);
        setWord(ea, data);
        cycles += 5;
    }
}

void emu816::op_asla(Addr ea)
{
    TRACE("ASL");

    if (e || p.f_m) {
        setc(a.b & 0x80);
        setnz_b(a.b <<= 1);
        setByte(ea, a.b);
    }
    else {
        setc(a.w & 0x8000);
        setnz_w(a.w <<= 1);
        setWord(ea, a.w);
    }
    cycles += 2;
}

void emu816::op_bcc(Addr ea)
{
    TRACE("BCC");

    if (p.f_c == 0) {
        if (e && ((pc ^ ea) & 0xff00)) ++cycles;
        pc = (Word)ea;
        cycles += 3;
    }
    else
        cycles += 2;
}

void emu816::op_bcs(Addr ea)
{
    TRACE("BCS");

    if (p.f_c == 1) {
        if (e && ((pc ^ ea) & 0xff00)) ++cycles;
        pc = (Word)ea;
        cycles += 3;
    }
    else
        cycles += 2;
}

void emu816::op_beq(Addr ea)
{
    TRACE("BEQ");

    if (p.f_z == 1) {
        if (e && ((pc ^ ea) & 0xff00)) ++cycles;
        pc = (Word)ea;
        cycles += 3;
    }
    else
        cycles += 2;
}

void emu816::op_bit(Addr ea)
{
    TRACE("BIT");

    if (e || p.f_m) {
        register Byte data = getByte(ea);

        setz((a.b & data) == 0);
        setn(data & 0x80);
        setv(data & 0x40);
        cycles += 2;
    }
    else {
        register Word data = getWord(ea);

        setz((a.w & data) == 0);
        setn(data & 0x8000);
        setv(data & 0x4000);

        cycles += 3;
    }
}

void emu816::op_biti(Addr ea)
{
    TRACE("BIT");

    if (e || p.f_m) {
        register Byte data = getByte(ea);

        setz((a.b & data) == 0);
    }
    else {
        register Word data = getWord(ea);

        setz((a.w & data) == 0);
    }
    cycles += 2;
}

void emu816::op_bmi(Addr ea)
{
    TRACE("BMI");

    if (p.f_n == 1) {
        if (e && ((pc ^ ea) & 0xff00)) ++cycles;
        pc = (Word)ea;
        cycles += 3;
    }
    else
        cycles += 2;
}

void emu816::op_bne(Addr ea)
{
    TRACE("BNE");

    if (p.f_z == 0) {
        if (e && ((pc ^ ea) & 0xff00)) ++cycles;
        pc = (Word)ea;
        cycles += 3;
    }
    else
        cycles += 2;
}

void emu816::op_bpl(Addr ea)
{
    TRACE("BPL");

    if (p.f_n == 0) {
        if (e && ((pc ^ ea) & 0xff00)) ++cycles;
        pc = (Word)ea;
        cycles += 3;
    }
    else
        cycles += 2;
}

void emu816::op_bra(Addr ea)
{
    TRACE("BRA");

    if (e && ((pc ^ ea) & 0xff00)) ++cycles;
    pc = (Word)ea;
    cycles += 3;
}

void emu816::op_brk(Addr ea)
{
    TRACE("BRK");

    if (e) {
        pushWord(pc);
        pushByte(p.b | 0x10);

        p.f_i = 1;
        p.f_d = 0;
        pbr = 0;

        pc = getWord(0xfffe);
        cycles += 7;
    }
    else {
        pushByte(pbr);
        pushWord(pc);
        pushByte(p.b);

        p.f_i = 1;
        p.f_d = 0;
        pbr = 0;

        pc = getWord(0xffe6);
        cycles += 8;
    }
}

void emu816::op_brl(Addr ea)
{
    TRACE("BRL");

    pc = (Word)ea;
    cycles += 3;
}

void emu816::op_bvc(Addr ea)
{
    TRACE("BVC");

    if (p.f_v == 0) {
        if (e && ((pc ^ ea) & 0xff00)) ++cycles;
        pc = (Word)ea;
        cycles += 3;
    }
    else
        cycles += 2;
}

void emu816::op_bvs(Addr ea)
{
    TRACE("BVS");

    if (p.f_v == 1) {
        if (e && ((pc ^ ea) & 0xff00)) ++cycles;
        pc = (Word)ea;
        cycles += 3;
    }
    else
        cycles += 2;
}

void emu816::op_clc(Addr ea)
{
    TRACE("CLC");

    setc(0);
    cycles += 2;
}

void emu816::op_cld(Addr ea)
{
    TRACE("CLD")

    setd(0);
    cycles += 2;
}

void emu816::op_cli(Addr ea)
{
    TRACE("CLI")

    seti(0);
    cycles += 2;
}

void emu816::op_clv(Addr ea)
{
    TRACE("CLD")

    setv(0);
    cycles += 2;
}

void emu816::op_cmp(Addr ea)
{
    TRACE("CMP");

    if (e || p.f_m) {
        Byte	data = getByte(ea);
        Word	temp = a.b - data;

        setc(temp & 0x100);
        setnz_b(lo(temp));
        cycles += 2;
    }
    else {
        Word	data = getWord(ea);
        Addr	temp = a.w - data;

        setc(temp & 0x10000L);
        setnz_w((Word)temp);
        cycles += 3;
    }
}

void emu816::op_cop(Addr ea)
{
    TRACE("COP");

    if (e) {
        pushWord(pc);
        pushByte(p.b);

        p.f_i = 1;
        p.f_d = 0;
        pbr = 0;

        pc = getWord(0xfff4);
        cycles += 7;
    }
    else {
        pushByte(pbr);
        pushWord(pc);
        pushByte(p.b);

        p.f_i = 1;
        p.f_d = 0;
        pbr = 0;

        pc = getWord(0xffe4);
        cycles += 8;
    }
}

void emu816::op_cpx(Addr ea)
{
    TRACE("CPX");

    if (e || p.f_x) {
        Byte	data = getByte(ea);
        Word	temp = x.b - data;

        setc(temp & 0x100);
        setnz_b(lo(temp));
        cycles += 2;
    }
    else {
        Word	data = getWord(ea);
        Addr	temp = x.w - data;

        setc(temp & 0x10000);
        setnz_w((Word) temp);
        cycles += 3;
    }
}

void emu816::op_cpy(Addr ea)
{
    TRACE("CPY");

    if (e || p.f_x) {
        Byte	data = getByte(ea);
        Word	temp = y.b - data;

        setc(temp & 0x100);
        setnz_b(lo(temp));
        cycles += 2;
    }
    else {
        Word	data = getWord(ea);
        Addr	temp = y.w - data;

        setc(temp & 0x10000);
        setnz_w((Word) temp);
        cycles += 3;
    }
}

void emu816::op_dec(Addr ea)
{
    TRACE("DEC");

    if (e || p.f_m) {
        register Byte data = getByte(ea);

        setByte(ea, --data);
        setnz_b(data);
        cycles += 4;
    }
    else {
        register Word data = getWord(ea);

        setWord(ea, --data);
        setnz_w(data);
        cycles += 5;
    }
}

void emu816::op_deca(Addr ea)
{
    TRACE("DEC");

    if (e || p.f_m)
        setnz_b(--a.b);
    else
        setnz_w(--a.w);

    cycles += 2;
}

void emu816::op_dex(Addr ea)
{
    TRACE("DEX");

    if (e || p.f_x)
        setnz_b(x.b -= 1);
    else
        setnz_w(x.w -= 1);

    cycles += 2;
}

void emu816::op_dey(Addr ea)
{
    TRACE("DEY");

    if (e || p.f_x)
        setnz_b(y.b -= 1);
    else
        setnz_w(y.w -= 1);

    cycles += 2;
}

void emu816::op_eor(Addr ea)
{
    TRACE("EOR");

    if (e || p.f_m) {
        setnz_b(a.b ^= getByte(ea));
        cycles += 2;
    }
    else {
        setnz_w(a.w ^= getWord(ea));
        cycles += 3;
    }
}

void emu816::op_inc(Addr ea)
{
    TRACE("INC");

    if (e || p.f_m) {
        register Byte data = getByte(ea);

        setByte(ea, ++data);
        setnz_b(data);
        cycles += 4;
    }
    else {
        register Word data = getWord(ea);

        setWord(ea, ++data);
        setnz_w(data);
        cycles += 5;
    }
}

void emu816::op_inca(Addr ea)
{
    TRACE("INC");

    if (e || p.f_m)
        setnz_b(++a.b);
    else
        setnz_w(++a.w);

    cycles += 2;
}

void emu816::op_inx(Addr ea)
{
    TRACE("INX");

    if (e || p.f_x)
        setnz_b(++x.b);
    else
        setnz_w(++x.w);

    cycles += 2;
}

void emu816::op_iny(Addr ea)
{
    TRACE("INY");

    if (e || p.f_x)
        setnz_b(++y.b);
    else
        setnz_w(++y.w);

    cycles += 2;
}

void emu816::op_jmp(Addr ea)
{
    TRACE("JMP");

    pbr = lo(ea >> 16);
    pc = (Word)ea;
    cycles += 1;
}

void emu816::op_jsl(Addr ea)
{
    TRACE("JSL");

    pushByte(pbr);
    pushWord(pc - 1);

    pbr = lo(ea >> 16);
    pc = (Word)ea;
    cycles += 5;
}

void emu816::op_jsr(Addr ea)
{
    TRACE("JSR");

    pushWord(pc - 1);

    pc = (Word)ea;
    cycles += 4;
}

void emu816::op_lda(Addr ea)
{
    TRACE("LDA");

    if (e || p.f_m) {
        setnz_b(a.b = getByte(ea));
        cycles += 2;
    }
    else {
        setnz_w(a.w = getWord(ea));
        cycles += 3;
    }
}

void emu816::op_ldx(Addr ea)
{
    TRACE("LDX");

    if (e || p.f_x) {
        setnz_b(lo(x.w = getByte(ea)));
        cycles += 2;
    }
    else {
        setnz_w(x.w = getWord(ea));
        cycles += 3;
    }
}

void emu816::op_ldy(Addr ea)
{
    TRACE("LDY");

    if (e || p.f_x) {
        setnz_b(lo(y.w = getByte(ea)));
        cycles += 2;
    }
    else {
        setnz_w(y.w = getWord(ea));
        cycles += 3;
    }
}

void emu816::op_lsr(Addr ea)
{
    TRACE("LSR");

    if (e || p.f_m) {
        register Byte data = getByte(ea);

        setc(data & 0x01);
        setnz_b(data >>= 1);
        setByte(ea, data);
        cycles += 4;
    }
    else {
        register Word data = getWord(ea);

        setc(data & 0x0001);
        setnz_w(data >>= 1);
        setWord(ea, data);
        cycles += 5;
    }
}

void emu816::op_lsra(Addr ea)
{
    TRACE("LSR");

    if (e || p.f_m) {
        setc(a.b & 0x01);
        setnz_b(a.b >>= 1);
        setByte(ea, a.b);
    }
    else {
        setc(a.w & 0x0001);
        setnz_w(a.w >>= 1);
        setWord(ea, a.w);
    }
    cycles += 2;
}

void emu816::op_mvn(Addr ea)
{
    TRACE("MVN");

    Byte src = getByte(ea + 1);
    Byte dst = getByte(ea + 0);

    setByte(join(dbr = dst, y.w++), getByte(join(src, x.w++)));
    if (--a.w != 0xffff) pc -= 3;
    cycles += 7;
}

void emu816::op_mvp(Addr ea)
{
    TRACE("MVP");

    Byte src = getByte(ea + 1);
    Byte dst = getByte(ea + 0);

    setByte(join(dbr = dst, y.w--), getByte(join(src, x.w--)));
    if (--a.w != 0xffff) pc -= 3;
    cycles += 7;
}

void emu816::op_nop(Addr ea)
{
    TRACE("NOP");

    cycles += 2;
}

void emu816::op_ora(Addr ea)
{
    TRACE("ORA");

    if (e || p.f_m) {
        setnz_b(a.b |= getByte(ea));
        cycles += 2;
    }
    else {
        setnz_w(a.w |= getWord(ea));
        cycles += 3;
    }
}

void emu816::op_pea(Addr ea)
{
    TRACE("PEA");

    pushWord(getWord(ea));
    cycles += 5;
}

void emu816::op_pei(Addr ea)
{
    TRACE("PEI");

    pushWord(getWord(ea));
    cycles += 6;
}

void emu816::op_per(Addr ea)
{
    TRACE("PER");

    pushWord((Word) ea);
    cycles += 6;
}

void emu816::op_pha(Addr ea)
{
    TRACE("PHA");

    if (e || p.f_m) {
        pushByte(a.b);
        cycles += 3;
    }
    else {
        pushWord(a.w);
        cycles += 4;
    }
}

void emu816::op_phb(Addr ea)
{
    TRACE("PHB");

    pushByte(dbr);
    cycles += 3;
}

void emu816::op_phd(Addr ea)
{
    TRACE("PHD");

    pushWord(dp.w);
    cycles += 4;
}

void emu816::op_phk(Addr ea)
{
    TRACE("PHK");

    pushByte(pbr);
    cycles += 3;
}

void emu816::op_php(Addr ea)
{
    TRACE("PHP");

    pushByte(p.b);
    cycles += 3;
}

void emu816::op_phx(Addr ea)
{
    TRACE("PHX");

    if (e || p.f_x) {
        pushByte(x.b);
        cycles += 3;
    }
    else {
        pushWord(x.w);
        cycles += 4;
    }
}

void emu816::op_phy(Addr ea)
{
    TRACE("PHY");

    if (e || p.f_x) {
        pushByte(y.b);
        cycles += 3;
    }
    else {
        pushWord(y.w);
        cycles += 4;
    }
}

void emu816::op_pla(Addr ea)
{
    TRACE("PLA");

    if (e || p.f_m) {
        setnz_b(a.b = pullByte());
        cycles += 4;
    }
    else {
        setnz_w(a.w = pullWord());
        cycles += 5;
    }
}

void emu816::op_plb(Addr ea)
{
    TRACE("PLB");

    setnz_b(dbr = pullByte());
    cycles += 4;
}

void emu816::op_pld(Addr ea)
{
    TRACE("PLD");

    setnz_w(dp.w = pullWord());
    cycles += 5;
}

void emu816::op_plk(Addr ea)
{
    TRACE("PLK");

    setnz_b(dbr = pullByte());
    cycles += 4;
}

void emu816::op_plp(Addr ea)
{
    TRACE("PLP");

    if (e)
        p.b = pullByte() | 0x30;
    else {
        p.b = pullByte();

        if (p.f_x) {
            x.w = x.b;
            y.w = y.b;
        }
    }
    cycles += 4;
}

void emu816::op_plx(Addr ea)
{
    TRACE("PLX");

    if (e || p.f_x) {
        setnz_b(lo(x.w = pullByte()));
        cycles += 4;
    }
    else {
        setnz_w(x.w = pullWord());
        cycles += 5;
    }
}

void emu816::op_ply(Addr ea)
{
    TRACE("PLY");

    if (e || p.f_x) {
        setnz_b(lo(y.w = pullByte()));
        cycles += 4;
    }
    else {
        setnz_w(y.w = pullWord());
        cycles += 5;
    }
}

void emu816::op_rep(Addr ea)
{
    TRACE("REP");

    p.b &= ~getByte(ea);
    if (e) p.f_m = p.f_x = 1;
    cycles += 3;
}

void emu816::op_rol(Addr ea)
{
    TRACE("ROL");

    if (e || p.f_m) {
        register Byte data = getByte(ea);
        register Byte carry = p.f_c ? 0x01 : 0x00;

        setc(data & 0x80);
        setnz_b(data = (data << 1) | carry);
        setByte(ea, data);
        cycles += 4;
    }
    else {
        register Word data = getWord(ea);
        register Word carry = p.f_c ? 0x0001 : 0x0000;

        setc(data & 0x8000);
        setnz_w(data = (data << 1) | carry);
        setWord(ea, data);
        cycles += 5;
    }
}

void emu816::op_rola(Addr ea)
{
    TRACE("ROL");

    if (e || p.f_m) {
        register Byte carry = p.f_c ? 0x01 : 0x00;

        setc(a.b & 0x80);
        setnz_b(a.b = (a.b << 1) | carry);
    }
    else {
        register Word carry = p.f_c ? 0x0001 : 0x0000;

        setc(a.w & 0x8000);
        setnz_w(a.w = (a.w << 1) | carry);
    }
    cycles += 2;
}

void emu816::op_ror(Addr ea)
{
    TRACE("ROR");

    if (e || p.f_m) {
        register Byte data = getByte(ea);
        register Byte carry = p.f_c ? 0x80 : 0x00;

        setc(data & 0x01);
        setnz_b(data = (data >> 1) | carry);
        setByte(ea, data);
        cycles += 4;
    }
    else {
        register Word data = getWord(ea);
        register Word carry = p.f_c ? 0x8000 : 0x0000;

        setc(data & 0x0001);
        setnz_w(data = (data >> 1) | carry);
        setWord(ea, data);
        cycles += 5;
    }
}

void emu816::op_rora(Addr ea)
{
    TRACE("ROR");

    if (e || p.f_m) {
        register Byte carry = p.f_c ? 0x80 : 0x00;

        setc(a.b & 0x01);
        setnz_b(a.b = (a.b >> 1) | carry);
    }
    else {
        register Word carry = p.f_c ? 0x8000 : 0x0000;

        setc(a.w & 0x0001);
        setnz_w(a.w = (a.w >> 1) | carry);
    }
    cycles += 2;
}

void emu816::op_rti(Addr ea)
{
    TRACE("RTI");

    if (e) {
        p.b = pullByte();
        pc = pullWord();
        cycles += 6;
    }
    else {
        p.b = pullByte();
        pc = pullWord();
        pbr = pullByte();
        cycles += 7;
    }
    p.f_i = 0;
}

void emu816::op_rtl(Addr ea)
{
    TRACE("RTL");

    pc = pullWord() + 1;
    pbr = pullByte();
    cycles += 6;
}

void emu816::op_rts(Addr ea)
{
    TRACE("RTS");

    pc = pullWord() + 1;
    cycles += 6;
}

void emu816::op_sbc(Addr ea)
{
    TRACE("SBC");

    if (e || p.f_m) {
        Byte	data = ~getByte(ea);
        Word	temp = a.b + data + p.f_c;
        
        if (p.f_d) {
            if ((temp & 0x0f) > 0x09) temp += 0x06;
            if ((temp & 0xf0) > 0x90) temp += 0x60;
        }

        setc(temp & 0x100);
        setv((~(a.b ^ data)) & (a.b ^ temp) & 0x80);
        setnz_b(a.b = lo(temp));
        cycles += 2;
    }
    else {
        Word	data = ~getWord(ea);
        int		temp = a.w + data + p.f_c;

        if (p.f_d) {
            if ((temp & 0x000f) > 0x0009) temp += 0x0006;
            if ((temp & 0x00f0) > 0x0090) temp += 0x0060;
            if ((temp & 0x0f00) > 0x0900) temp += 0x0600;
            if ((temp & 0xf000) > 0x9000) temp += 0x6000;
        }

        setc(temp & 0x10000);
        setv((~(a.w ^ data)) & (a.w ^ temp) & 0x8000);
        setnz_w(a.w = (Word)temp);
        cycles += 3;
    }
}

void emu816::op_sec(Addr ea)
{
    TRACE("SEC");

    setc(1);
    cycles += 2;
}

void emu816::op_sed(Addr ea)
{
    TRACE("SED");

    setd(1);
    cycles += 2;
}

void emu816::op_sei(Addr ea)
{
    TRACE("SEI");

    seti(1);
    cycles += 2;
}

void emu816::op_sep(Addr ea)
{
    TRACE("SEP");

    p.b |= getByte(ea);
    if (e) p.f_m = p.f_x = 1;

    if (p.f_x) {
        x.w = x.b;
        y.w = y.b;
    }
    cycles += 3;
}

void emu816::op_sta(Addr ea)
{
    TRACE("STA");

    if (e || p.f_m) {
        setByte(ea, a.b);
        cycles += 2;
    }
    else {
        setWord(ea, a.w);
        cycles += 3;
    }
}

void emu816::op_stp(Addr ea)
{
    TRACE("STP");

    if (!interrupted) {
        pc -= 1;
    }
    else
        interrupted = false;

    cycles += 3;
}

void emu816::op_stx(Addr ea)
{
    TRACE("STX");

    if (e || p.f_x) {
        setByte(ea, x.b);
        cycles += 2;
    }
    else {
        setWord(ea, x.w);
        cycles += 3;
    }
}

void emu816::op_sty(Addr ea)
{
    TRACE("STY");

    if (e || p.f_x) {
        setByte(ea, y.b);
        cycles += 2;
    }
    else {
        setWord(ea, y.w);
        cycles += 3;
    }
}

void emu816::op_stz(Addr ea)
{
    TRACE("STZ");

    if (e || p.f_m) {
        setByte(ea, 0);
        cycles += 2;
    }
    else {
        setWord(ea, 0);
        cycles += 3;
    }
}

void emu816::op_tax(Addr ea)
{
    TRACE("TAX");

    if (e || p.f_x)
        setnz_b(lo(x.w = a.b));
    else
        setnz_w(x.w = a.w);

    cycles += 2;
}

void emu816::op_tay(Addr ea)
{
    TRACE("TAY");

    if (e || p.f_x)
        setnz_b(lo(y.w = a.b));
    else
        setnz_w(y.w = a.w);

    cycles += 2;
}

void emu816::op_tcd(Addr ea)
{
    TRACE("TCD");

    dp.w = a.w;
    cycles += 2;
}

void emu816::op_tdc(Addr ea)
{
    TRACE("TDC");

    if (e || p.f_m)
        setnz_b(lo(a.w = dp.w));
    else
        setnz_w(a.w = dp.w);

    cycles += 2;
}

void emu816::op_tcs(Addr ea)
{
    TRACE("TCS");

    sp.w = e ? (0x0100 | a.b) : a.w;
    cycles += 2;
}

void emu816::op_trb(Addr ea)
{
    TRACE("TRB");

    if (e || p.f_m) {
        register Byte data = getByte(ea);

        setByte(ea, data & ~a.b);
        setz((a.b & data) == 0);
        cycles += 4;
    }
    else {
        register Word data = getWord(ea);

        setWord(ea, data & ~a.w);
        setz((a.w & data) == 0);
        cycles += 5;
    }
}

void emu816::op_tsb(Addr ea)
{
    TRACE("TSB");

    if (e || p.f_m) {
        register Byte data = getByte(ea);

        setByte(ea, data | a.b);
        setz((a.b & data) == 0);
        cycles += 4;
    }
    else {
        register Word data = getWord(ea);

        setWord(ea, data | a.w);
        setz((a.w & data) == 0);
        cycles += 5;
    }
}

void emu816::op_tsc(Addr ea)
{
    TRACE("TSC");

    if (e || p.f_m)
        setnz_b(lo(a.w = sp.w));
    else
        setnz_w(a.w = sp.w);

    cycles += 2;
}

void emu816::op_tsx(Addr ea)
{
    TRACE("TSX");

    if (e)
        setnz_b(x.b = sp.b);
    else
        setnz_w(x.w = sp.w);

    cycles += 2;
}

void emu816::op_txa(Addr ea)
{
    TRACE("TXA");

    if (e || p.f_m)
        setnz_b(a.b = x.b);
    else
        setnz_w(a.w = x.w);

    cycles += 2;
}

void emu816::op_txs(Addr ea)
{
    TRACE("TXS");

    if (e)
        sp.w = 0x0100 | x.b;
    else
        sp.w = x.w;

    cycles += 2;
}

void emu816::op_txy(Addr ea)
{
    TRACE("TXY");

    if (e || p.f_x)
        setnz_b(lo(y.w = x.w));
    else
        setnz_w(y.w = x.w);

    cycles += 2;
}

void emu816::op_tya(Addr ea)
{
    TRACE("TYA");

    if (e || p.f_m)
        setnz_b(a.b = y.b);
    else
        setnz_w(a.w = y.w);

    cycles += 2;
}

void emu816::op_tyx(Addr ea)
{
    TRACE("TYX");

    if (e || p.f_x)
        setnz_b(lo(x.w = y.w));
    else
        setnz_w(x.w = y.w);

    cycles += 2;
}

void emu816::op_wai(Addr ea)
{
    TRACE("WAI");

    if (!interrupted) {
        pc -= 1;
    }
    else
        interrupted = false;

    cycles += 3;
}

void emu816::op_wdm(Addr ea)
{
    TRACE("WDM");

    switch (getByte(ea)) {
    case 0x01:	cout << (char) a.b; break;
    case 0x02:  cin >> a.b; break;
    case 0xff:	stopped = true;  break;
    }
    cycles += 3;
}

void emu816::op_xba(Addr ea)
{
    TRACE("XBA");

    a.w = swap(a.w);
    setnz_b(a.b);
    cycles += 3;
}

void emu816::op_xce(Addr ea)
{
    TRACE("XCE");

    Byte	oe = e;

    e = p.f_c;
    p.f_c = oe;

    if (e) {
        p.b |= 0x30;
        sp.w = 0x0100 | sp.b;
    }
    cycles += 2;
}