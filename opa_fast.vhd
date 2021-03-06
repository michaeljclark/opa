--  opa: Open Processor Architecture
--  Copyright (C) 2014-2016  Wesley W. Terpstra
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
--
--  To apply the GPL to my VHDL, please follow these definitions:
--    Program        - The entire collection of VHDL in this project and any
--                     netlist or floorplan derived from it.
--    System Library - Any macro that translates directly to hardware
--                     e.g. registers, IO pins, or memory blocks
--    
--  My intent is that if you include OPA into your project, all of the HDL
--  and other design files that go into the same physical chip must also
--  be released under the GPL. If this does not cover your usage, then you
--  must consult me directly to receive the code under a different license.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.opa_pkg.all;
use work.opa_isa_base_pkg.all;
use work.opa_functions_pkg.all;
use work.opa_components_pkg.all;

entity opa_fast is
    generic(
      g_isa    : t_opa_isa;
      g_config : t_opa_config;
      g_target : t_opa_target);
    port(
      clk_i          : in  std_logic;
      rst_n_i        : in  std_logic;
      
      regfile_stb_i  : in  std_logic;
      regfile_rega_i : in  std_logic_vector(f_opa_reg_wide(g_config)-1 downto 0);
      regfile_regb_i : in  std_logic_vector(f_opa_reg_wide(g_config)-1 downto 0);
      regfile_arg_i  : in  std_logic_vector(f_opa_arg_wide(g_config)-1 downto 0);
      regfile_imm_i  : in  std_logic_vector(f_opa_imm_wide(g_isa)   -1 downto 0);
      regfile_pc_i   : in  std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
      regfile_pcf_i  : in  std_logic_vector(f_opa_fet_wide(g_config)-1 downto 0);
      regfile_pcn_i  : in  std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
      regfile_regx_o : out std_logic_vector(f_opa_reg_wide(g_config)-1 downto 0);
      
      issue_oldest_i : in  std_logic;
      issue_retry_o  : out std_logic;
      issue_fault_o  : out std_logic;
      issue_pc_o     : out std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
      issue_pcf_o    : out std_logic_vector(f_opa_fet_wide(g_config)-1 downto 0);
      issue_pcn_o    : out std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa)));
end opa_fast;

architecture rtl of opa_fast is

  constant c_imm_wide : natural := f_opa_imm_wide(g_isa);
  constant c_adr_wide : natural := f_opa_adr_wide(g_config);
  constant c_sum_wide : natural := f_opa_choose(c_imm_wide<c_adr_wide,c_imm_wide,c_adr_wide);

  signal s_arg   : t_opa_arg;
  signal s_adder : t_opa_adder;
  signal s_lut   : std_logic_vector(3 downto 0);

  signal r_rega : std_logic_vector(regfile_rega_i'range);
  signal r_regb : std_logic_vector(regfile_regb_i'range);
  signal r_imm  : std_logic_vector(regfile_imm_i'range);
  signal r_pcf  : std_logic_vector(regfile_pcf_i'range);
  signal r_pc   : std_logic_vector(regfile_pc_i'range);
  signal r_pcn  : std_logic_vector(regfile_pcn_i'range);
  signal r_pcf1 : std_logic_vector(regfile_pcf_i'range);
  signal r_pc1  : std_logic_vector(regfile_pc_i'range);
  signal r_pcn1 : std_logic_vector(regfile_pcn_i'range);
  
  signal r_lut  : std_logic_vector(3 downto 0);
  signal r_nota : std_logic;
  signal r_notb : std_logic;
  signal r_cin  : std_logic;
  signal r_sign : std_logic;
  signal r_eq   : std_logic;
  signal r_fault: std_logic;
  signal r_mode : std_logic_vector(1 downto 0);

  type t_logic is array(natural range <>) of unsigned(1 downto 0);
  signal s_logic_in : t_logic(r_rega'range);
  
  signal s_logic      : std_logic_vector(r_rega'range);
  signal s_nota       : std_logic_vector(r_rega'range);
  signal s_notb       : std_logic_vector(r_rega'range);
  signal s_eq         : std_logic_vector(r_rega'range);
  signal s_widea      : std_logic_vector(r_rega'left+2 downto 0);
  signal s_wideb      : std_logic_vector(r_rega'left+2 downto 0);
  signal s_widex      : std_logic_vector(r_rega'left+2 downto 0);
  signal s_sum_low    : std_logic_vector(r_rega'range);
  signal s_comparison : std_logic_vector(r_rega'range);
  signal s_pc_next_pad: std_logic_vector(r_rega'range) := (others => '0');
  
  signal s_pc_imm     : unsigned(regfile_pcn_i'range);
  signal s_pc_next    : std_logic_vector(regfile_pcn_i'range);
  signal r_pc_next    : std_logic_vector(regfile_pcn_i'range);
  signal r_pc_jump    : std_logic_vector(regfile_pcn_i'range);
  signal r_pc_sum     : std_logic_vector(regfile_pcn_i'range);
  signal r_fmux       : std_logic_vector(1 downto 0);
  signal s_br_fault   : std_logic;
  signal s_br_target  : std_logic_vector(regfile_pcn_i'range);

  attribute dont_merge : boolean;
  attribute maxfan     : natural;
  
  -- Do not merge these registers; they are used in different places!
  attribute dont_merge of r_lut  : signal is true;
  attribute dont_merge of r_eq   : signal is true;
  attribute dont_merge of r_nota : signal is true;
  attribute dont_merge of r_notb : signal is true;
  attribute dont_merge of r_cin  : signal is true;
  attribute dont_merge of r_sign : signal is true;
  attribute dont_merge of r_fault: signal is true;
  attribute dont_merge of r_mode : signal is true;
  
  -- These are fanned out to 64 bits; make it easier to fit
  -- attribute maxfan of r_lut  : signal is 8;
  -- attribute maxfan of r_mode : signal is 8;
begin

  s_arg   <= f_opa_arg_from_vec(regfile_arg_i);
  s_adder <= s_arg.adder;
  s_lut   <= s_arg.lut;
  
  -- Register our inputs
  main : process(clk_i) is
  begin
    if rising_edge(clk_i) then
      r_rega <= regfile_rega_i;
      r_regb <= regfile_regb_i;
      r_imm  <= regfile_imm_i;
      r_pcf  <= regfile_pcf_i;
      r_pc   <= regfile_pc_i;
      r_pcn  <= regfile_pcn_i;
      
      r_mode <= s_arg.fmode;
      r_lut  <= s_lut;
      r_eq   <= s_adder.eq;
      r_nota <= s_adder.nota;
      r_notb <= s_adder.notb;
      r_cin  <= s_adder.cin;
      r_sign <= s_adder.sign;
      r_fault<= s_adder.fault;
    end if;
  end process;
  
  -- Result is a logic function
  logic : for i in r_rega'range generate
    s_logic_in(i)(1) <= r_rega(i);
    s_logic_in(i)(0) <= r_regb(i);
    s_logic(i) <= f_opa_index(r_lut, s_logic_in(i));
  end generate;
  
  -- Result is an adder function
  s_nota <= (others => r_nota);
  s_notb <= (others => r_notb);
  s_eq   <= (others => r_eq);
  s_widea(r_rega'left+2) <= '0';
  s_wideb(r_rega'left+2) <= '0';
  -- !!! this is too slow: ... find a way to get it into the adder
  s_widea(r_rega'left+1 downto 1) <= s_nota xor r_rega xor (r_regb and s_eq);
  s_wideb(r_rega'left+1 downto 1) <= s_notb xor (r_regb and not s_eq);
  s_widea(0) <= '1';
  s_wideb(0) <= r_cin;
  s_widex <= std_logic_vector(unsigned(s_widea) + unsigned(s_wideb));
  s_sum_low <= s_widex(r_rega'left+1 downto 1);
  
  -- Result is a comparison
  s_comparison(0) <= s_widex(r_rega'left+2) xor ((r_rega(31) xor r_regb(31)) and r_sign);
  s_comparison(r_rega'left downto 1) <= (others => '0');
  
  -- Result is a jump return address
  s_pc_next <= std_logic_vector(unsigned(r_pc) + 1);
  s_pc_next_pad(s_pc_next'high-1 downto s_pc_next'low) <= std_logic_vector(s_pc_next(s_pc_next'high-1 downto s_pc_next'low));
  s_pc_next_pad(r_rega'high downto s_pc_next'high) <= (others => s_pc_next(s_pc_next'high));
  
  -- Send result to regfile
  with r_mode select
  regfile_regx_o <= 
    s_logic         when c_opa_fast_lut,
    s_sum_low       when c_opa_fast_addl,
    s_comparison    when c_opa_fast_addh,
    s_pc_next_pad   when c_opa_fast_jump,
    (others => 'X') when others;
  
  -- Pack immediate into sum format
  s_pc_imm(c_sum_wide-2 downto r_pc'low)  <= unsigned(r_imm(c_sum_wide-2 downto r_pc'low));
  s_pc_imm(r_pc'high downto c_sum_wide-1) <= (others => r_imm(c_sum_wide-1));
  
  faults : process(clk_i) is
  begin
    if rising_edge(clk_i) then
      r_pcf1 <= r_pcf;
      r_pc1  <= r_pc;
      r_pcn1 <= r_pcn;
      r_pc_next <= s_pc_next;
      r_pc_jump <= std_logic_vector(unsigned(r_pc) + s_pc_imm);
      r_pc_sum  <= s_sum_low(r_pc_sum'range);
      case r_mode is
        when c_opa_fast_lut  => r_fmux <= "11";
        when c_opa_fast_addl => r_fmux <= "11";
        when c_opa_fast_addh => r_fmux(0) <= not r_fault or s_comparison(0);
                                r_fmux(1) <= not r_fault;
        when c_opa_fast_jump => r_fmux <= "10";
        when others          => r_fmux <= "XX";
      end case;
    end if;
  end process;
  
  with r_fmux select
  s_br_fault <=
    not f_opa_eq(r_pc_next, r_pcn1) when "00", -- addh, fault, and comparison=0
    not f_opa_eq(r_pc_jump, r_pcn1) when "01", -- addh, fault, and comparison=1
    not f_opa_eq(r_pc_sum,  r_pcn1) when "10", -- jump
    '0'                             when "11",
    'X'                             when others;
    
  with r_fmux select
  s_br_target <= 
    r_pc_next       when "00",
    r_pc_jump       when "01",
    r_pc_sum        when "10",
    (others => 'X') when others;
  
  issue_retry_o   <= s_br_fault;
  issue_fault_o   <= s_br_fault and issue_oldest_i;
  issue_pcf_o     <= r_pcf1;
  issue_pc_o      <= r_pc1;
  issue_pcn_o     <= s_br_target;
  
end rtl;
