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
use work.opa_isa_pkg.all;

entity opa_decode is
  generic(
    g_isa    : t_opa_isa;
    g_config : t_opa_config;
    g_target : t_opa_target);
  port(
    clk_i          : in  std_logic;
    rst_n_i        : in  std_logic;

    -- Predicted jumps?
    predict_hit_i    : in  std_logic;
    predict_jump_i   : in  std_logic_vector(f_opa_fetchers(g_config)-1 downto 0);
    
    -- Push a return stack entry
    predict_push_o   : out std_logic;
    predict_ret_o    : out std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
    
    -- Fixup PC to new target
    predict_fault_o  : out std_logic;
    predict_return_o : out std_logic;
    predict_jump_o   : out std_logic_vector(f_opa_fetchers(g_config)-1 downto 0);
    predict_source_o : out std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
    predict_target_o : out std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
    predict_return_i : in  std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));

    -- Instructions delivered from icache
    icache_stb_i     : in  std_logic;
    icache_stall_o   : out std_logic;
    icache_pc_i      : in  std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
    icache_pcn_i     : in  std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
    icache_dat_i     : in  std_logic_vector(f_opa_fetch_bits(g_isa,g_config)-1 downto 0);
    
    -- Feed data to the renamer
    rename_stb_o   : out std_logic;
    rename_stall_i : in  std_logic;
    rename_fast_o  : out std_logic_vector(f_opa_renamers(g_config)-1 downto 0);
    rename_slow_o  : out std_logic_vector(f_opa_renamers(g_config)-1 downto 0);
    rename_order_o : out std_logic_vector(f_opa_renamers(g_config)-1 downto 0);
    rename_setx_o  : out std_logic_vector(f_opa_renamers(g_config)-1 downto 0);
    rename_geta_o  : out std_logic_vector(f_opa_renamers(g_config)-1 downto 0);
    rename_getb_o  : out std_logic_vector(f_opa_renamers(g_config)-1 downto 0);
    rename_aux_o   : out std_logic_vector(f_opa_aux_wide(g_config)-1 downto 0);
    rename_archx_o : out t_opa_matrix(f_opa_renamers(g_config)-1 downto 0, f_opa_arch_wide(g_isa)-1 downto 0);
    rename_archa_o : out t_opa_matrix(f_opa_renamers(g_config)-1 downto 0, f_opa_arch_wide(g_isa)-1 downto 0);
    rename_archb_o : out t_opa_matrix(f_opa_renamers(g_config)-1 downto 0, f_opa_arch_wide(g_isa)-1 downto 0);

    -- Accept faults
    rename_fault_i : in  std_logic;
    rename_pc_i    : in  std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
    rename_pcf_i   : in  std_logic_vector(f_opa_fet_wide(g_config)-1 downto 0);
    rename_pcn_i   : in  std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
    
    -- Give the regfile the information EUs will need for these operations
    regfile_stb_o  : out std_logic;
    regfile_aux_o  : out std_logic_vector(f_opa_aux_wide(g_config)-1 downto 0);
    regfile_arg_o  : out t_opa_matrix(f_opa_renamers(g_config)-1 downto 0, f_opa_arg_wide(g_config)-1 downto 0);
    regfile_imm_o  : out t_opa_matrix(f_opa_renamers(g_config)-1 downto 0, f_opa_imm_wide(g_isa)   -1 downto 0);
    regfile_pc_o   : out t_opa_matrix(f_opa_renamers(g_config)-1 downto 0, f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa));
    regfile_pcf_o  : out t_opa_matrix(f_opa_renamers(g_config)-1 downto 0, f_opa_fet_wide(g_config)-1 downto 0);
    regfile_pcn_o  : out std_logic_vector(f_opa_adr_wide(g_config)-1 downto f_opa_op_align(g_isa)));
end opa_decode;

architecture rtl of opa_decode is

  constant c_big_endian:boolean := f_opa_big_endian(g_isa);
  constant c_op_align : natural := f_opa_op_align(g_isa);
  constant c_op_wide  : natural := f_opa_op_wide (g_isa);
  constant c_imm_wide : natural := f_opa_imm_wide(g_isa);
  constant c_arch_wide: natural := f_opa_arch_wide(g_isa);
  constant c_fetchers : natural := f_opa_fetchers(g_config);
  constant c_renamers : natural := f_opa_renamers(g_config);
  constant c_buffers  : natural := c_fetchers + 2*c_renamers - 1;
  constant c_num_aux  : natural := f_opa_num_aux (g_config);
  constant c_adr_wide : natural := f_opa_adr_wide(g_config);
  constant c_fet_wide : natural := f_opa_fet_wide(g_config);
  constant c_buf_wide : natural := f_opa_log2(c_buffers+1); -- [0, c_buffers] inclusive
  constant c_aux_wide : natural := f_opa_aux_wide(g_config);
  constant c_fetch_align : natural := f_opa_fetch_align(g_isa,g_config);
  
  constant c_min_imm_pc : natural := f_opa_choose(c_imm_wide<c_adr_wide, c_imm_wide, c_adr_wide);
  
  type t_op_array  is array(natural range <>) of t_opa_op;
  type t_pc_array  is array(natural range <>) of std_logic_vector(c_adr_wide-1 downto c_op_align);
  type t_pcf_array is array(natural range <>) of std_logic_vector(c_fet_wide-1 downto 0);
  
  function f_flip(x : natural) return natural is
  begin
    if c_big_endian then
      return c_fetchers-1-x;
    else
      return x;
    end if;
  end f_flip;

  signal s_pc_off      : unsigned(c_fet_wide-1 downto 0);
  signal s_ops_in      : t_op_array(c_fetchers-1 downto 0);
  signal s_pc_in       : t_pc_array(c_fetchers-1 downto 0);
  signal s_immb_in     : t_pc_array(c_fetchers-1 downto 0);
  signal s_pred_in     : t_pc_array(c_fetchers-1 downto 0);
  signal s_mask_skip   : std_logic_vector(c_fetchers-1 downto 0);
  signal s_mask_tail   : std_logic_vector(c_fetchers-1 downto 0);
  signal s_jump        : std_logic_vector(c_fetchers-1 downto 0);
  signal s_take        : std_logic_vector(c_fetchers-1 downto 0);
  signal s_force       : std_logic_vector(c_fetchers-1 downto 0);
  signal s_push        : std_logic_vector(c_fetchers-1 downto 0);
  signal s_pop         : std_logic_vector(c_fetchers-1 downto 0);
  
  signal s_hit         : std_logic_vector(c_fetchers-1 downto 0);
  signal s_bad_jump    : std_logic_vector(c_fetchers-1 downto 0);
  signal s_use_static  : std_logic;
  signal r_use_static  : std_logic := '0';
  
  signal s_static_jumps  : std_logic_vector(c_fetchers-1 downto 0);
  signal s_static_jump   : std_logic_vector(c_fetchers-1 downto 0);
  signal s_static_targets: t_opa_matrix(c_fetchers-1 downto 0, c_adr_wide-1 downto c_op_align);
  signal s_static_target : std_logic_vector(c_adr_wide-1 downto c_op_align);
  
  signal s_rename_jump   : std_logic_vector(c_fetchers-1 downto 0);
  signal s_rename_source : std_logic_vector(c_adr_wide-1 downto c_op_align);
  
  signal s_jump_taken : std_logic_vector(c_fetchers-1 downto 0);
  signal s_ret_taken  : std_logic;
  signal s_pcn_taken  : std_logic_vector(c_adr_wide-1 downto c_op_align);
  signal r_pcn_taken  : std_logic_vector(c_adr_wide-1 downto c_op_align);
  signal s_jal_pc     : std_logic_vector(c_adr_wide-1 downto c_op_align);

  signal s_ops      : t_op_array (c_buffers-1 downto 0);
  signal r_ops      : t_op_array (c_buffers-1 downto 0);
  signal s_pc       : t_pc_array (c_buffers-1 downto 0);
  signal r_pc       : t_pc_array (c_buffers-1 downto 0);
  signal s_pcf      : t_pcf_array(c_buffers-1 downto 0);
  signal r_pcf      : t_pcf_array(c_buffers-1 downto 0);
  
  signal s_stb      : std_logic;
  signal s_stall    : std_logic;
  signal s_pcn_reg  : std_logic;
  signal s_progress : std_logic;
  signal s_accept   : std_logic;
  signal s_ops_sub  : unsigned(c_fet_wide-1 downto 0);
  signal r_fill     : unsigned(c_buf_wide-1 downto 0) := (others => '0');
  signal r_aux      : unsigned(c_aux_wide-1 downto 0) := (others => '0');
  
begin

  check : process(clk_i) is
  begin
    if rising_edge(clk_i) then
      -- control inputs (safe for when/if)
      assert (f_opa_safe(predict_hit_i)    = '1') report "decode: predict_hit_i has metavalue" severity failure;
      assert (f_opa_safe(predict_jump_i)   = '1') report "decode: predict_jump_i has metavalue" severity failure;
      assert (f_opa_safe(icache_stb_i)     = '1') report "decode: icache_stb_i has metavalue" severity failure;
      assert (f_opa_safe(rename_stall_i)   = '1') report "decode: rename_stall_i has metavalue" severity failure;
      assert (f_opa_safe(rename_fault_i)   = '1') report "decode: rename_fault_i has metavalue" severity failure;
      -- combinatorial control (safe for when/if)
      assert (f_opa_safe(s_stall)      = '1') report "decode: s_stall has metavalue" severity failure;
      assert (f_opa_safe(s_stb)        = '1') report "decode: s_stb has metavalue" severity failure;
      assert (f_opa_safe(s_pcn_reg)    = '1') report "decode: s_pcn_reg has metavalue" severity failure;
      assert (f_opa_safe(s_progress)   = '1') report "decode: s_progress has metavalue" severity failure;
      assert (f_opa_safe(s_accept)     = '1') report "decode: s_accept has metavalue"   severity failure;
      -- registered control
      assert (f_opa_safe(r_use_static) = '1') report "decode: r_use_static has metavalue" severity failure;
      assert (f_opa_safe(r_fill)       = '1') report "decode: r_fill has metavalue" severity failure;
      assert (f_opa_safe(r_aux)        = '1') report "decode: r_aux has metavalue" severity failure;
    end if;
  end process;

  -- Decode the flow control information from the instructions
  off1p : if c_fetchers > 1 generate
    s_pc_off <= unsigned(icache_pc_i(c_fetch_align-1 downto c_op_align));
    s_ops_sub <= unsigned(f_opa_1hot_dec(f_opa_reverse(s_jump_taken))) + s_pc_off;
  end generate;
  off1 : if c_fetchers = 1 generate
    s_pc_off  <= "0";
    s_ops_sub <= "0";
  end generate;
  
  s_mask_tail(0) <= '0';
  decode : for i in 0 to c_fetchers-1 generate
    s_ops_in(i) <= f_opa_isa_decode(g_isa, g_config, icache_dat_i((f_flip(i)+1)*c_op_wide-1 downto f_flip(i)*c_op_wide));
    fet1 : if c_fetchers = 1 generate
      s_pc_in(i)  <= icache_pc_i(c_adr_wide-1 downto c_fetch_align);
    end generate;
    fet1p : if c_fetchers > 1 generate
      s_pc_in(i)  <= icache_pc_i(c_adr_wide-1 downto c_fetch_align) & std_logic_vector(to_unsigned(i, c_fet_wide));
    end generate;
    
    s_immb_in(i)(c_min_imm_pc-2 downto c_op_align) <= s_ops_in(i).immb(c_min_imm_pc-2 downto c_op_align);
    s_immb_in(i)(c_adr_wide-1 downto c_min_imm_pc-1) <= (others => s_ops_in(i).immb(c_min_imm_pc-1));
    
    s_pred_in(i) <= std_logic_vector(unsigned(s_pc_in(i)) + unsigned(s_immb_in(i)));
    
    s_mask_skip(i)  <= f_opa_lt(i, s_pc_off); -- Unused ops before loaded PC
    tail : if i > 0 generate
      s_mask_tail(i)  <= s_mask_tail(i-1) or predict_jump_i(i-1); -- Ops following a taken jump
    end generate;
    
    s_jump(i)  <= s_ops_in(i).jump;
    s_take(i)  <= s_ops_in(i).take;
    s_force(i) <= s_ops_in(i).force;
    s_pop(i)   <= s_ops_in(i).pop;
    s_push(i)  <= s_ops_in(i).push;
  end generate;
  
  -- Decide if we want to accept the fetch prediction
  s_hit <= (others => predict_hit_i);
  s_bad_jump <= ((not s_jump and predict_jump_i) or
                 (s_force and not predict_jump_i) or
                 (s_take and not s_hit))
                and not s_mask_skip and not s_mask_tail;
  s_use_static <= f_opa_or(s_bad_jump);
  
  -- What is our prediction?
  s_static_jumps<= s_take and not s_mask_skip; -- need to assign valid range before picking
  s_static_jump <= f_opa_pick_small(s_static_jumps);
  
  targets : for d in 0 to c_fetchers-1 generate
    bits : for b in c_op_align to c_adr_wide-1 generate
      s_static_targets(d,b) <= s_pred_in(d)(b);
    end generate;
  end generate;
  s_static_target <= f_opa_product(f_opa_transpose(s_static_targets), s_static_jump);

  s_jump_taken <= f_opa_mux(s_use_static, s_static_jump, predict_jump_i);
  s_ret_taken  <= f_opa_or(s_pop and s_static_jump);
  
  -- pcn MUST be what gets loaded next, b/c instructions compare against it.
  -- if issue faults, all this gets blown away, so that doesn't matter
  -- if there is no fault, the usual prediction goes through the pipeline
  -- if decode faults, then we need to pick whatever the predictor picks!
  -- the predictor will always go where we tell it, except for a return.
  s_pcn_taken  <= 
    f_opa_mux(s_use_static,
      f_opa_mux(s_ret_taken, predict_return_i, s_static_target),
      icache_pcn_i);
  
  -- Decode renamer's fault information
  s_rename_source(c_adr_wide-1    downto c_fetch_align) <= rename_pc_i(c_adr_wide-1 downto c_fetch_align);
  src_fet1p : if c_fetchers > 1 generate
    s_rename_source(c_fetch_align-1 downto c_op_align)  <= rename_pcf_i;
    jumps : for i in 0 to c_fetchers-1 generate
      s_rename_jump(i) <= f_opa_eq(unsigned(rename_pc_i(c_fetch_align-1 downto c_op_align)), i);
    end generate;
  end generate;
  src_fet1 : if c_fetchers = 1 generate
    s_rename_jump <= "1";
  end generate;
  
  -- Feed back information to fetch
  predict_fault_o  <= (s_use_static and s_accept) or rename_fault_i;
  predict_return_o <= s_accept and not rename_fault_i and s_ret_taken;
  
  predict_jump_o   <= s_rename_jump   when rename_fault_i='1' else s_static_jump;
  predict_source_o <= s_rename_source when rename_fault_i='1' else icache_pc_i;
  predict_target_o <= rename_pcn_i    when rename_fault_i='1' else s_static_target;
  
  -- Do we need to push the PC?
  s_jal_pc(c_adr_wide   -1 downto c_fetch_align) <= icache_pc_i(c_adr_wide-1 downto c_fetch_align);
  subpc : if c_fetchers > 1 generate
    s_jal_pc(c_fetch_align-1 downto c_op_align)  <= f_opa_1hot_dec(s_jump_taken);
  end generate;
  predict_push_o <= f_opa_or(s_push and s_jump_taken) and s_accept;
  predict_ret_o  <= std_logic_vector(1 + unsigned(s_jal_pc));
  
  -- Flow control from fetch and to rename
  s_stall    <= '1' when r_fill >= 2*c_renamers else '0';
  s_stb      <= '1' when r_fill >=   c_renamers else '0';
  s_pcn_reg  <= '1' when r_fill =    c_renamers else '0';
  s_progress <= s_stb and not rename_stall_i;
  s_accept   <= icache_stb_i and not r_use_static and not s_stall;
  
  -- Select the new buffer fill state
  buf1p : if c_fetchers > 1 generate
    index : block is
      type t_idx_array is array(natural range <>) of unsigned(c_fet_wide-1 downto 0);
      signal s_idx_base : unsigned(c_fet_wide-1 downto 0);
      signal s_idx      : t_idx_array(c_buffers-1 downto 0);
    begin
      s_idx_base <= s_pc_off - r_fill(s_idx_base'range);
      ops : for i in 0 to c_buffers-1 generate
        s_idx(i) <= s_idx_base + to_unsigned(i mod c_fetchers, c_fet_wide);
        s_ops(i) <= r_ops(i) when i < r_fill else s_ops_in(to_integer(s_idx(i))) when f_opa_safe(s_idx(i))='1' else c_opa_op_undef;
        s_pc (i) <= r_pc (i) when i < r_fill else s_pc_in (to_integer(s_idx(i))) when f_opa_safe(s_idx(i))='1' else (others => 'X');
        s_pcf(i) <= r_pcf(i) when i < r_fill else icache_pc_i(c_fetch_align-1 downto c_op_align);
      end generate;
    end block;
  end generate;
  buf1 : if c_fetchers = 1 generate
    ops : for i in 0 to c_buffers-1 generate
      s_ops(i) <= r_ops(i) when i < r_fill else s_ops_in(0);
      s_pc (i) <= r_pc (i) when i < r_fill else s_pc_in (0);
      s_pcf(i) <= "0";
    end generate;
  end generate;
  
  fill : process(clk_i, rst_n_i) is
  begin
    if rst_n_i = '0' then
      r_use_static <= '0';
      r_fill <= (others => '0');
    elsif rising_edge(clk_i) then
      if rename_fault_i = '1' then
        r_use_static <= '1';
        r_fill <= (others => '0');
      else
        -- On a static predicition, we ignore the next valid icache strobe
        if (icache_stb_i and not s_stall) = '1' then
          if r_use_static = '1' then
            r_use_static <= '0';
          else
            r_use_static <= s_use_static;
          end if;
        end if;
        
        if s_progress = '1' then
          if s_accept = '1' then
            r_fill <= (r_fill + c_fetchers) - c_renamers - s_ops_sub;
          else
            r_fill <= r_fill - c_renamers;
          end if;
        else
          if s_accept = '1' then
            r_fill <= (r_fill + c_fetchers) - s_ops_sub;
          else
            r_fill <= r_fill;
          end if;
        end if;
      end if;
    end if;
  end process;
  
  aux : process(clk_i, rst_n_i) is
  begin
    if rst_n_i = '0' then
      r_aux <= (others => '0');
    elsif rising_edge(clk_i) then
      if s_progress = '1' then
        if r_aux = c_num_aux-1 then
          r_aux <= (others => '0');
        else
          r_aux <= r_aux+1;
        end if;
      end if;
    end if;
  end process;
  
  main : process(clk_i) is
  begin
    if rising_edge(clk_i) then
      if s_progress = '1' then
        r_ops(c_buffers-c_renamers-1 downto 0) <= s_ops(c_buffers-1 downto c_renamers);
        r_pcf(c_buffers-c_renamers-1 downto 0) <= s_pcf(c_buffers-1 downto c_renamers);
        r_pc (c_buffers-c_renamers-1 downto 0) <= s_pc (c_buffers-1 downto c_renamers);
      else
        r_ops <= s_ops;
        r_pcf <= s_pcf;
        r_pc  <= s_pc;
      end if;
    end if;
  end process;
  
  latch_pcn : process(clk_i) is
  begin
    if rising_edge(clk_i) then
      if s_accept = '1' then
        r_pcn_taken <= s_pcn_taken;
      end if;
    end if;
  end process;
  
  icache_stall_o <= s_stall and not rename_fault_i;
  
  rename_stb_o <= s_stb;
  rename_aux_o <= std_logic_vector(r_aux);
  ops_out : for d in 0 to c_renamers-1 generate
    rename_fast_o (d) <= r_ops(d).fast;
    rename_slow_o (d) <= not r_ops(d).fast;
    rename_order_o(d) <= r_ops(d).order;
    rename_setx_o (d) <= r_ops(d).setx;
    rename_geta_o (d) <= r_ops(d).geta;
    rename_getb_o (d) <= r_ops(d).getb;
    bits : for b in 0 to c_arch_wide-1 generate
      rename_archx_o(d,b) <= r_ops(d).archx(b);
      rename_archa_o(d,b) <= r_ops(d).archa(b);
      rename_archb_o(d,b) <= r_ops(d).archb(b);
    end generate;
  end generate;
  
  regfile_stb_o <= s_stb;
  regfile_aux_o <= std_logic_vector(r_aux);
  rf_out : for d in 0 to c_renamers-1 generate
    arg : for b in 0 to c_arg_wide-1 generate
      regfile_arg_o(d,b) <= f_opa_vec_from_arg(r_ops(d).arg)(b);
    end generate;
    imm : for b in 0 to c_imm_wide-1 generate
      regfile_imm_o(d,b) <= r_ops(d).imm(b);
    end generate;
    pc : for b in c_op_align to c_adr_wide-1 generate
      regfile_pc_o(d,b) <= r_pc(d)(b);
    end generate;
    pcf : for b in 0 to c_fet_wide-1 generate
      regfile_pcf_o(d,b) <= r_pcf(d)(b);
    end generate;
  end generate;
  pcn : for b in c_op_align to c_adr_wide-1 generate
    regfile_pcn_o(b) <= r_pcn_taken(b) when s_pcn_reg='1' else r_pc(c_renamers)(b);
  end generate;
  
end rtl;
