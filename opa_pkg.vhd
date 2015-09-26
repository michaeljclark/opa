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

-- Open Processor Architecture
package opa_pkg is

  type t_opa_config is record
    log_width  : natural; -- 2**log_width  = # of bits in registers
    adr_width  : natural; -- Virtual address space
    num_decode : natural; -- # of instructions decoded concurrently
    num_stat   : natural; -- # of reservation stations
    num_fast   : natural; -- # of fast EUs (logic, add/sub, branch, ...)
    num_slow   : natural; -- # of slow EUs (load/store, mul, fp, ...)
    ieee_fp    : boolean; -- Floating point support
    dc_ways    : natural; -- Data cache ways (each is 4KB=page_size)
    dtlb_ways  : natural; -- Data TLB ways
  end record;
  
  -- 16-bit processor, 1-issue,  6 stations, 1+1 EU, 4KB dcache
  constant c_opa_tiny  : t_opa_config := ( 4, 16, 1,  6, 1, 1, false, 1, 1);
  
  -- 32-bit processor, 2-issue, 18 stations, 1+1 EU, 8KB dcache
  constant c_opa_small : t_opa_config := ( 5, 22, 2, 18, 1, 1, false, 2, 1);
  
  -- 32-bit processor, 4-issue, 28 stations, 2+1 EU, 16KB dcache
  constant c_opa_large : t_opa_config := ( 5, 32, 4, 28, 2, 1, false, 4, 4);
  
  -- 64-bit processor, 4-issue, 48 stations, 2+2 EU, 32KB dcache
  constant c_opa_huge  : t_opa_config := ( 6, 39, 4, 44, 2, 2, true,  8, 4);
  
  type t_opa_target is record
    lut_width  : natural; -- How many inputs to combine at once
    add_width  : natural; -- Hardware support for simultaneous adders
    mul_width  : natural; -- Widest DSP multiplier block
    mem_depth  : natural; -- Minimum depth of a memory block
    post_adder : boolean; -- Can add two products (a*b)<<wide + (c*d)
  end record;
  
  -- FPGA flavors supported
  constant c_opa_cyclone_iv : t_opa_target := (4, 2, 18, 256, true);
  constant c_opa_arria_ii   : t_opa_target := (6, 2, 18, 256, true);
  constant c_opa_cyclone_v  : t_opa_target := (6, 3, 27, 256, false);
  constant c_opa_asic       : t_opa_target := (4, 2,  1,   1, false);
  
  component opa is
    generic(
      g_config  : t_opa_config;
      g_target  : t_opa_target);
    port(
      clk_i     : in  std_logic;
      rst_n_i   : in  std_logic;

      -- Wishbone instruction bus
      i_cyc_o   : out std_logic;
      i_stb_o   : out std_logic;
      i_stall_i : in  std_logic;
      i_ack_i   : in  std_logic;
      i_err_i   : in  std_logic;
      i_addr_o  : out std_logic_vector(2**g_config.log_width  -1 downto 0);
      i_data_i  : in  std_logic_vector(2**g_config.log_width  -1 downto 0);
      
      -- Wishbone data bus
      d_cyc_o   : out std_logic;
      d_stb_o   : out std_logic;
      d_we_o    : out std_logic;
      d_stall_i : in  std_logic;
      d_ack_i   : in  std_logic;
      d_err_i   : in  std_logic;
      d_addr_o  : out std_logic_vector(2**g_config.log_width  -1 downto 0);
      d_sel_o   : out std_logic_vector(2**g_config.log_width/8-1 downto 0);
      d_data_o  : out std_logic_vector(2**g_config.log_width  -1 downto 0);
      d_data_i  : in  std_logic_vector(2**g_config.log_width  -1 downto 0);
      
      -- Execution unit acitivity indication
      status_o  : out std_logic_vector(g_config.num_fast+g_config.num_slow-1 downto 0));
  end component;
  
end package;
