library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity tb_super_smoke is
end entity;

architecture sim of tb_super_smoke is

  constant C_K_MAX  : natural := 64;
  constant C_ADDR_W : natural := 13;
  constant C_P      : natural := 8;

  signal clk, rst  : std_logic := '0';
  signal start     : std_logic := '0';
  signal n_iter    : unsigned(3 downto 0) := to_unsigned(2, 4);
  signal k_len     : unsigned(C_ADDR_W-1 downto 0) := to_unsigned(64, C_ADDR_W);
  signal f1, f2    : unsigned(C_ADDR_W-1 downto 0) := (others => '0');
  signal in_valid  : std_logic := '0';
  signal in_idx    : unsigned(C_ADDR_W-1 downto 0) := (others => '0');
  signal l_sys_in  : llr_t := to_signed(1, llr_t'length);
  signal l_par1_in : llr_t := to_signed(1, llr_t'length);
  signal l_par2_in : llr_t := to_signed(1, llr_t'length);
  signal out_valid : std_logic;
  signal out_idx   : unsigned(C_ADDR_W-1 downto 0);
  signal l_post    : llr_t;
  signal done      : std_logic;

begin

  uut: entity work.turbo_decoder_top
    generic map (
      G_K_MAX  => C_K_MAX,
      G_ADDR_W => C_ADDR_W,
      G_P      => C_P
    )
    port map (
      clk       => clk,
      rst       => rst,
      start     => start,
      n_iter    => n_iter,
      k_len     => k_len,
      f1        => f1,
      f2        => f2,
      in_valid  => in_valid,
      in_idx    => in_idx,
      l_sys_in  => l_sys_in,
      l_par1_in => l_par1_in,
      l_par2_in => l_par2_in,
      out_valid => out_valid,
      out_idx   => out_idx,
      l_post    => l_post,
      done      => done
    );

  clk <= not clk after 5 ns;

  process
  begin
    rst <= '1';
    wait for 20 ns;
    rst <= '0';
    wait for 10 ns;

    start <= '1';
    f1 <= to_unsigned(11, C_ADDR_W);
    f2 <= to_unsigned(24, C_ADDR_W);
    
    for i in 0 to 63 loop
      in_valid <= '1';
      in_idx <= to_unsigned(i, C_ADDR_W);
      l_sys_in <= to_signed((i mod 8) + 1, llr_t'length);
      wait for 10 ns;
    end loop;
    in_valid <= '0';
    start <= '0';
    
    wait for 5000 ns;
    report "Test completed";
    std.env.stop;
  end process;

end architecture;