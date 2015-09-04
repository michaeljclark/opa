library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.opa_pkg.all;
use work.opa_isa_base_pkg.all;
use work.opa_functions_pkg.all;

-- LM32 ISA
package opa_isa_pkg is
  constant c_op_wide : natural := 32;
  function f_decode(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op;
end package;

package body opa_isa_pkg is

  -- Registers with special meaning
  constant c_lm32_ra : std_logic_vector(4 downto 0) := "11101"; -- ra=29
  constant c_lm32_ea : std_logic_vector(4 downto 0) := "11110"; -- ea=30
  constant c_lm32_ba : std_logic_vector(4 downto 0) := "11111"; -- ba=31
  
  function f_parse_rrtype (x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := c_opa_op_bad;
    constant c_zero : std_logic_vector(10 downto 0) := (others => '0');
  begin
    result.bad   := f_opa_bit(x(10 downto 0) /= c_zero);
    result.jump  := c_opa_jump_never;
    result.archb := x(20 downto 16);
    result.archa := x(25 downto 21);
    result.archx := x(15 downto 11);
    result.getb  := '1';
    result.geta  := '1';
    result.setx  := '1';
    return result;
  end f_parse_rrtype;
  
  function f_parse_ritype(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := c_opa_op_bad;
  begin
    result.jump  := c_opa_jump_never;
    result.archa := x(25 downto 21);
    result.archx := x(20 downto 16);
    result.getb  := '0'; -- immediate
    result.geta  := '1';
    result.setx  := '1';
    -- parsing of immediate done in si(gned), lo(w), hi(gh), in(dex)
    return result;
  end f_parse_ritype;

  function f_parse_sitype(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := f_parse_ritype(x);
  begin
    result.bad := '0';
    result.imm := (others => x(15));
    result.imm(14 downto 0) := x(14 downto 0);
    return result;
  end f_parse_sitype;

  function f_parse_lotype(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := f_parse_ritype(x);
  begin
    result.bad := '0';
    result.imm := (others => '0');
    result.imm(15 downto 0) := x(15 downto 0);
    return result;
  end f_parse_lotype;

  function f_parse_hitype(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := f_parse_ritype(x);
  begin
    result.bad := '0';
    result.imm := (others => '0');
    result.imm(31 downto 16) := x(15 downto 0);
    return result;
  end f_parse_hitype;

  function f_parse_intype(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := f_parse_ritype(x);
    constant c_zero : std_logic_vector(10 downto 0) := (others => '0');
  begin
    result.bad := f_opa_bit(x(15 downto 5) /= c_zero);
    result.imm := (others => '-');
    result.imm(4 downto 0) := x(4 downto 0);
    return result;
  end f_parse_intype;
  
  function f_parse_bitype(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := c_opa_op_bad;
  begin
    result.bad   := '0';
    if x(15) = '1' then
      result.jump := c_opa_jump_often; -- static prediction: negative = taken
    else
      result.jump := c_opa_jump_seldom;
    end if;
    result.dest  := c_opa_jump_add_immediate;
    result.push  := '0';
    result.archb := x(20 downto 16);
    result.archa := x(25 downto 21);
    result.getb  := '1';
    result.geta  := '1';
    result.setx  := '0';
    result.imm := (others => x(15));
    result.imm(16 downto 2) := x(14 downto 0);
    result.imm( 1 downto 0) := (others => '0');
    return result;
  end f_parse_bitype;

  function f_parse_jitype(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := c_opa_op_bad;
  begin
    result.bad  := '0';
    result.jump := c_opa_jump_always;
    result.dest := c_opa_jump_add_immediate;
    result.getb := '0';
    result.geta := '0';
    -- NOTE: caller must assign setx and push
    result.imm := (others => x(25));
    result.imm(26 downto 2) := x(24 downto 0);
    result.imm( 1 downto 0) := (others => '0');
    return result;
  end f_parse_jitype;

  function f_parse_jrtype(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable result : t_opa_op := c_opa_op_bad;
    constant c_zero : std_logic_vector(20 downto 0) := (others => '0');
  begin
    result.bad   := f_opa_bit(x(20 downto 0) /= c_zero);
    result.jump  := c_opa_jump_always;
    result.dest  := c_opa_jump_unknown;
    result.archa := x(25 downto 21);
    result.getb  := '0';
    result.geta  := '1';
    -- NOTE: caller must assign setx and push
    result.imm := (others => '0'); -- necessary as it is added to PC/reg
    return result;
  end f_parse_jrtype;
  
  ------------------------------------------------------------------------------------------
  
  function f_decode_b(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_jrtype(x);
    if op.archx = c_lm32_ra or op.archx = c_lm32_ba or op.archx = c_lm32_ea then
      op.dest := c_opa_jump_return_stack;
    end if;
    -- !!! mess around with CSRs on eret/bret
    adder.eq    := '0';
    adder.nota  := '0';
    adder.notb  := '0';
    adder.cin   := '0';
    adder.sign  := '-';
    adder.fault := '-';
    fast.mode   := c_opa_fast_jump;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.setx     := '0';
    op.push     := '0';
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_b;
  
  function f_decode_bi(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_jitype(x);
    adder.eq    := '0';
    adder.nota  := '0';
    adder.notb  := '0';
    adder.cin   := '0';
    adder.sign  := '-';
    adder.fault := '-';
    fast.mode   := c_opa_fast_jump;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.setx     := '0';
    op.push     := '0';
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_bi;
  
  function f_decode_call(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_jrtype(x);
    adder.eq    := '0';
    adder.nota  := '0';
    adder.notb  := '0';
    adder.cin   := '0';
    adder.sign  := '-';
    adder.fault := '-';
    fast.mode   := c_opa_fast_jump;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.archx    := c_lm32_ra;
    op.setx     := '1';
    op.push     := '1';
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_call;
  
  function f_decode_calli(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_jitype(x);
    adder.eq    := '0';
    adder.nota  := '0';
    adder.notb  := '0';
    adder.cin   := '0';
    adder.sign  := '-';
    adder.fault := '-';
    fast.mode   := c_opa_fast_jump;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.archx    := c_lm32_ra;
    op.setx     := '1';
    op.push     := '1';
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_calli;

  ------------------------------------------------------------------------------------------

  function f_decode_add(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    adder.eq    := '0';
    adder.nota  := '0';
    adder.notb  := '0';
    adder.cin   := '0';
    adder.sign  := '-';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addl;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_add;
  
  function f_decode_sub(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    adder.eq    := '0';
    adder.nota  := '0';
    adder.notb  := '1';
    adder.cin   := '1';
    adder.sign  := '-';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addl;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_sub;
  
  function f_decode_addi(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    adder.eq    := '0';
    adder.nota  := '0';
    adder.notb  := '0';
    adder.cin   := '0';
    adder.sign  := '-';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addl;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_addi;
  
  ------------------------------------------------------------------------------------------
  
  function f_decode_and(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("1000"); -- X = A and B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_and;
  
  function f_decode_andhi(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_hitype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("1000"); -- X = A and B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_andhi;
  
  function f_decode_andi(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_lotype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("1000"); -- X = A and B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_andi;
  
  function f_decode_or(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("1110"); -- X = A or B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_or;
  
  function f_decode_ori(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_lotype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("1110"); -- X = A or B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_ori;
  
  function f_decode_orhi(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_hitype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("1110"); -- X = A or B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_orhi;

  function f_decode_nor(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("0001"); -- X = A nor B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_nor;
  
  function f_decode_nori(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_lotype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("0001"); -- X = A nor B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_nori;

  function f_decode_xor(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("0110"); -- X = A xor B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_xor;
  
  function f_decode_xori(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_lotype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("0110"); -- X = A xor B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_xori;

  function f_decode_xnor(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("1001"); -- X = A xnor B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_xnor;
  
  function f_decode_xnori(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_lotype(x);
    fast.mode := c_opa_fast_lut;
    fast.raw  := f_opa_fast_from_lut("1001"); -- X = A xnor B
    op.fast   := '1';
    op.arg    := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_xnori;

  ------------------------------------------------------------------------------------------
  
  function f_decode_be(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_bitype(x);
    adder.eq    := '1';
    adder.nota  := '1';
    adder.notb  := '0';
    adder.cin   := '1';
    adder.sign  := '0';
    adder.fault := '1';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_be;
  
  function f_decode_cmpe(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    adder.eq    := '1';
    adder.nota  := '1';
    adder.notb  := '0';
    adder.cin   := '1';
    adder.sign  := '0';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpe;
  
  function f_decode_cmpei(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    adder.eq    := '1';
    adder.nota  := '1';
    adder.notb  := '0';
    adder.cin   := '1';
    adder.sign  := '0';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpei;
  
  function f_decode_bne(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_bitype(x);
    adder.eq    := '1';
    adder.nota  := '0';
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '0';
    adder.fault := '1';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_bne;
  
  function f_decode_cmpne(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    adder.eq    := '1';
    adder.nota  := '0';
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '0';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpne;
  
  function f_decode_cmpnei(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    adder.eq    := '1';
    adder.nota  := '0';
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '0';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpnei;
  
  function f_decode_bg(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_bitype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>b)=(a-b-1>=0)=overflow(a-b-1)=overflow(a+!b)
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '1';
    adder.fault := '1';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_bg;

  function f_decode_cmpg(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>b)=(a-b-1>=0)=overflow(a-b-1)=overflow(a+!b)
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '1';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpg;
  
  function f_decode_cmpgi(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>b)=(a-b-1>=0)=overflow(a-b-1)=overflow(a+!b)
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '1';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpgi;
  
  function f_decode_bgu(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_bitype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>b)=(a-b-1>=0)=overflow(a-b-1)=overflow(a+!b)
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '0';
    adder.fault := '1';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_bgu;
  
  function f_decode_cmpgu(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>b)=(a-b-1>=0)=overflow(a-b-1)=overflow(a+!b)
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '0';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpgu;
  
  function f_decode_cmpgui(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_lotype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>b)=(a-b-1>=0)=overflow(a-b-1)=overflow(a+!b)
    adder.notb  := '1';
    adder.cin   := '0';
    adder.sign  := '0';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpgui;

  function f_decode_bge(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_bitype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>=b)=(a-b>=0)=overflow(a-b)=overflow(a+!b+1)
    adder.notb  := '1';
    adder.cin   := '1';
    adder.sign  := '1';
    adder.fault := '1';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_bge;
  
  function f_decode_cmpge(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>=b)=(a-b>=0)=overflow(a-b)=overflow(a+!b+1)
    adder.notb  := '1';
    adder.cin   := '1';
    adder.sign  := '1';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpge;
  
  function f_decode_cmpgei(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>=b)=(a-b>=0)=overflow(a-b)=overflow(a+!b+1)
    adder.notb  := '1';
    adder.cin   := '1';
    adder.sign  := '1';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpgei;
  
  function f_decode_bgeu(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_bitype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>=b)=(a-b>=0)=overflow(a-b)=overflow(a+!b+1)
    adder.notb  := '1';
    adder.cin   := '1';
    adder.sign  := '0';
    adder.fault := '1';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_bgeu;
  
  function f_decode_cmpgeu(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>=b)=(a-b>=0)=overflow(a-b)=overflow(a+!b+1)
    adder.notb  := '1';
    adder.cin   := '1';
    adder.sign  := '0';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpgeu;
  
  function f_decode_cmpgeui(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable adder : t_opa_adder;
    variable fast  : t_opa_fast;
    variable op    : t_opa_op;
  begin
    op := f_parse_lotype(x);
    adder.eq    := '0';
    adder.nota  := '0'; -- x=(a>=b)=(a-b>=0)=overflow(a-b)=overflow(a+!b+1)
    adder.notb  := '1';
    adder.cin   := '1';
    adder.sign  := '0';
    adder.fault := '0';
    fast.mode   := c_opa_fast_addh;
    fast.raw    := f_opa_fast_from_adder(adder);
    op.fast     := '1';
    op.arg      := f_opa_arg_from_fast(fast);
    return op;
  end f_decode_cmpgeui;

  ------------------------------------------------------------------------------------------
  
  function f_decode_mul(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable mul  : t_opa_mul;
    variable slow : t_opa_slow;
    variable op   : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    mul.sexta   := '-';
    mul.sextb   := '-';
    mul.high    := '0';
    mul.divide  := '0';
    slow.mode   := c_opa_slow_mul;
    slow.raw    := f_opa_slow_from_mul(mul);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_mul;

  function f_decode_muli(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable mul  : t_opa_mul;
    variable slow : t_opa_slow;
    variable op   : t_opa_op;
  begin
    op := f_parse_sitype(x);
    mul.sexta   := '-';
    mul.sextb   := '-';
    mul.high    := '0';
    mul.divide  := '0';
    slow.mode   := c_opa_slow_mul;
    slow.raw    := f_opa_slow_from_mul(mul);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_muli;
  
  function f_decode_mulh(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable mul  : t_opa_mul;
    variable slow : t_opa_slow;
    variable op   : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    mul.sexta   := '0';
    mul.sextb   := '0';
    mul.high    := '1';
    mul.divide  := '0';
    slow.mode   := c_opa_slow_mul;
    slow.raw    := f_opa_slow_from_mul(mul);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_mulh;

  function f_decode_mulhi(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable mul  : t_opa_mul;
    variable slow : t_opa_slow;
    variable op   : t_opa_op;
  begin
    op := f_parse_sitype(x);
    mul.sexta   := '0';
    mul.sextb   := '0';
    mul.high    := '1';
    mul.divide  := '0';
    slow.mode   := c_opa_slow_mul;
    slow.raw    := f_opa_slow_from_mul(mul);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_mulhi;
  
  function f_decode_div(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable mul  : t_opa_mul;
    variable slow : t_opa_slow;
    variable op   : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    mul.sexta   := '-';
    mul.sextb   := '1';
    mul.high    := '0';
    mul.divide  := '1';
    slow.mode   := c_opa_slow_mul;
    slow.raw    := f_opa_slow_from_mul(mul);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_div;

  function f_decode_divu(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable mul  : t_opa_mul;
    variable slow : t_opa_slow;
    variable op   : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    mul.sexta   := '-';
    mul.sextb   := '0';
    mul.high    := '0';
    mul.divide  := '1';
    slow.mode   := c_opa_slow_mul;
    slow.raw    := f_opa_slow_from_mul(mul);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_divu;

  function f_decode_modu(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable mul  : t_opa_mul;
    variable slow : t_opa_slow;
    variable op   : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    mul.sexta   := '0';
    mul.sextb   := '0';
    mul.high    := '1';
    mul.divide  := '1';
    slow.mode   := c_opa_slow_mul;
    slow.raw    := f_opa_slow_from_mul(mul);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_modu;
  
  ------------------------------------------------------------------------------------------
  
  function f_decode_lb(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable ldst  : t_opa_ldst;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    ldst.size   := c_opa_ldst_byte;
    ldst.sext   := '1';
    slow.mode   := c_opa_slow_load;
    slow.raw    := f_opa_slow_from_ldst(ldst);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_lb;
  
  function f_decode_lbu(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable ldst  : t_opa_ldst;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    ldst.size   := c_opa_ldst_byte;
    ldst.sext   := '0';
    slow.mode   := c_opa_slow_load;
    slow.raw    := f_opa_slow_from_ldst(ldst);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_lbu;

  function f_decode_lh(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable ldst  : t_opa_ldst;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    ldst.size   := c_opa_ldst_half;
    ldst.sext   := '1';
    slow.mode   := c_opa_slow_load;
    slow.raw    := f_opa_slow_from_ldst(ldst);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_lh;
  
  function f_decode_lhu(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable ldst  : t_opa_ldst;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    ldst.size   := c_opa_ldst_half;
    ldst.sext   := '0';
    slow.mode   := c_opa_slow_load;
    slow.raw    := f_opa_slow_from_ldst(ldst);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_lhu;

  function f_decode_lw(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable ldst  : t_opa_ldst;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    ldst.size   := c_opa_ldst_word;
    ldst.sext   := '1';
    slow.mode   := c_opa_slow_load;
    slow.raw    := f_opa_slow_from_ldst(ldst);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_lw;

  function f_decode_sb(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable ldst  : t_opa_ldst;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    ldst.size   := c_opa_ldst_byte;
    ldst.sext   := '-';
    slow.mode   := c_opa_slow_store;
    slow.raw    := f_opa_slow_from_ldst(ldst);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_sb;
  
  function f_decode_sh(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable ldst  : t_opa_ldst;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    ldst.size   := c_opa_ldst_half;
    ldst.sext   := '-';
    slow.mode   := c_opa_slow_store;
    slow.raw    := f_opa_slow_from_ldst(ldst);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_sh;
  
  function f_decode_sw(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable ldst  : t_opa_ldst;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_sitype(x);
    ldst.size   := c_opa_ldst_word;
    ldst.sext   := '-';
    slow.mode   := c_opa_slow_store;
    slow.raw    := f_opa_slow_from_ldst(ldst);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_sw;
  
  ------------------------------------------------------------------------------------------
  
  function f_decode_sl(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable shift : t_opa_shift;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    shift.right := '0';
    shift.sext  := '0';
    slow.mode   := c_opa_slow_shift;
    slow.raw    := f_opa_slow_from_shift(shift);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_sl;
  
  function f_decode_sli(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable shift : t_opa_shift;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_intype(x);
    shift.right := '0';
    shift.sext  := '0';
    slow.mode   := c_opa_slow_shift;
    slow.raw    := f_opa_slow_from_shift(shift);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_sli;
  
  function f_decode_sr(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable shift : t_opa_shift;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    shift.right := '1';
    shift.sext  := '1';
    slow.mode   := c_opa_slow_shift;
    slow.raw    := f_opa_slow_from_shift(shift);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_sr;
  
  function f_decode_sri(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable shift : t_opa_shift;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_intype(x);
    shift.right := '1';
    shift.sext  := '1';
    slow.mode   := c_opa_slow_shift;
    slow.raw    := f_opa_slow_from_shift(shift);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_sri;
  
  function f_decode_sru(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable shift : t_opa_shift;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_rrtype(x);
    shift.right := '1';
    shift.sext  := '0';
    slow.mode   := c_opa_slow_shift;
    slow.raw    := f_opa_slow_from_shift(shift);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_sru;
  
  function f_decode_srui(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    variable shift : t_opa_shift;
    variable slow  : t_opa_slow;
    variable op    : t_opa_op;
  begin
    op := f_parse_intype(x);
    shift.right := '1';
    shift.sext  := '0';
    slow.mode   := c_opa_slow_shift;
    slow.raw    := f_opa_slow_from_shift(shift);
    op.fast     := '0';
    op.arg      := f_opa_arg_from_slow(slow);
    return op;
  end f_decode_srui;

  ------------------------------------------------------------------------------------------
  
  function f_decode(x : std_logic_vector(c_op_wide-1 downto 0)) return t_opa_op is
    constant c_opcode : std_logic_vector(5 downto 0) := x(31 downto 26);
  begin
    case c_opcode is
      when "101101" => return f_decode_add(x);
      when "001101" => return f_decode_addi(x);
      when "101000" => return f_decode_and(x);
      when "011000" => return f_decode_andhi(x);
      when "001000" => return f_decode_andi(x);
      when "110000" => return f_decode_b(x); -- ret(b ra), bret(b ba), eret(b ea)
      when "010001" => return f_decode_be(x);
      when "010010" => return f_decode_bg(x);
      when "010011" => return f_decode_bge(x);
      when "010100" => return f_decode_bgeu(x);
      when "010101" => return f_decode_bgu(x);
      when "111000" => return f_decode_bi(x);
      when "010111" => return f_decode_bne(x);
      when "110110" => return f_decode_call(x);
      when "111110" => return f_decode_calli(x);
      when "111001" => return f_decode_cmpe(x);
      when "011001" => return f_decode_cmpei(x);
      when "111010" => return f_decode_cmpg(x);
      when "011010" => return f_decode_cmpgi(x);
      when "111011" => return f_decode_cmpge(x);
      when "011011" => return f_decode_cmpgei(x);
      when "111100" => return f_decode_cmpgeu(x);
      when "011100" => return f_decode_cmpgeui(x);
      when "111101" => return f_decode_cmpgu(x);
      when "011101" => return f_decode_cmpgui(x);
      when "111111" => return f_decode_cmpne(x);
      when "011111" => return f_decode_cmpnei(x);
      when "100111" => return f_decode_div(x);
      when "100011" => return f_decode_divu(x);
      when "000100" => return f_decode_lb(x);
      when "010000" => return f_decode_lbu(x);
      when "000111" => return f_decode_lh(x);
      when "001011" => return f_decode_lhu(x);
      when "001010" => return f_decode_lw(x);
      when "110001" => return f_decode_modu(x);
      when "100010" => return f_decode_mul(x);
      when "000010" => return f_decode_muli(x);
      when "101010" => return f_decode_mulh(x);  -- An OPA extension
      when "110011" => return f_decode_mulhi(x); -- An OPA extension
      when "100001" => return f_decode_nor(x);
      when "000001" => return f_decode_nori(x);
      when "101110" => return f_decode_or(x);
      when "001110" => return f_decode_ori(x);
      when "011110" => return f_decode_orhi(x);
      when "101011" => return c_opa_op_bad; -- !!! raise: break, scall
      when "100100" => return c_opa_op_bad; -- !!! rcsr
      when "001100" => return f_decode_sb(x);
      when "101100" => return c_opa_op_bad; -- !!! sextb
      when "110111" => return c_opa_op_bad; -- !!! sexth
      when "000011" => return f_decode_sh(x);
      when "101111" => return f_decode_sl(x);
      when "001111" => return f_decode_sli(x);
      when "100101" => return f_decode_sr(x);
      when "000101" => return f_decode_sri(x);
      when "100000" => return f_decode_sru(x);
      when "000000" => return f_decode_srui(x);
      when "110010" => return f_decode_sub(x);
      when "010110" => return f_decode_sw(x);
      when "110100" => return c_opa_op_bad; -- !!! wcsr
      when "101001" => return f_decode_xnor(x);
      when "001001" => return f_decode_xnori(x);
      when "100110" => return f_decode_xor(x);
      when "000110" => return f_decode_xori(x);
      when others   => return c_opa_op_bad;
    end case;
  end f_decode;
end opa_isa_pkg;