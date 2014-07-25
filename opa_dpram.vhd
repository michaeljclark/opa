library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.opa_pkg.all;
use work.opa_functions_pkg.all;
use work.opa_components_pkg.all;

entity opa_dpram is
  generic(
    g_width : natural;
    g_size  : natural);
  port(
    clk_i    : in  std_logic;
    rst_n_i  : in  std_logic;
    r_en_i   : in  std_logic;
    r_addr_i : in  std_logic_vector(f_opa_log2(g_size)-1 downto 0);
    r_data_o : out std_logic_vector(g_width-1 downto 0);
    w_en_i   : in  std_logic;
    w_addr_i : in  std_logic_vector(f_opa_log2(g_size)-1 downto 0);
    w_data_i : in  std_logic_vector(g_width-1 downto 0));
end opa_dpram;

architecture rtl of opa_dpram is
  type t_memory is array(g_size-1 downto 0) of std_logic_vector(g_width-1 downto 0);
  signal r_memory : t_memory;
  
  signal r_addr : std_logic_vector(r_addr_i'range);
begin

  r_data_o <= r_memory(to_integer(unsigned(r_addr)));
  
  main : process(clk_i) is
  begin
    if rising_edge(clk_i) then
      r_addr <= r_addr_i;
      
      if w_en_i = '1' then
        r_memory(to_integer(unsigned(w_addr_i))) <= w_data_i;
      end if;
    end if;
  end process;

end rtl;