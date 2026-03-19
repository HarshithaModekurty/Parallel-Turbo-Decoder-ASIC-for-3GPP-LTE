library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.turbo_pkg.all;

entity tb_block_decode is
end entity;

architecture test of tb_block_decode is
  constant G_K_MAX  : natural := 6144;
  constant G_ADDR_W : natural := 13;
  constant G_P      : natural := 8;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal start     : std_logic := '0';
  signal n_iter    : unsigned(3 downto 0) := x"8";
  signal k_len     : unsigned(G_ADDR_W-1 downto 0) := to_unsigned(6144, G_ADDR_W);
  signal f1        : unsigned(G_ADDR_W-1 downto 0) := to_unsigned(263, G_ADDR_W);
  signal f2        : unsigned(G_ADDR_W-1 downto 0) := to_unsigned(480, G_ADDR_W);
  signal in_valid  : std_logic := '0';
  signal in_idx    : unsigned(G_ADDR_W-1 downto 0) := (others => '0');
  signal l_sys_in  : llr_t := (others => '0');
  signal l_par1_in : llr_t := (others => '0');
  signal l_par2_in : llr_t := (others => '0');

  signal out_valid : std_logic;
  signal out_idx   : unsigned(G_P*G_ADDR_W-1 downto 0);
  signal l_post    : signed(G_P*7-1 downto 0);
  signal done      : std_logic;

  -- Testbench file and reporting
  file f_in : text open read_mode is "sim_vectors/lte_frame_input_vectors.txt";

begin

  clk <= not clk after 5 ns;

  uut : entity work.turbo_decoder_top
    generic map (
      G_K_MAX => G_K_MAX, G_ADDR_W => G_ADDR_W, G_P => G_P
    )
    port map (
      clk => clk, rst => rst,
      start => start, n_iter => n_iter,
      k_len => k_len, f1 => f1, f2 => f2,
      in_valid => in_valid, in_idx => in_idx,
      l_sys_in => l_sys_in, l_par1_in => l_par1_in, l_par2_in => l_par2_in,
      out_valid => out_valid, out_idx => out_idx, l_post => l_post,
      done => done
    );

  process
    variable L_in : line;
    variable t_sys, t_p1, t_p2 : integer;
    variable i : integer := 0;
  begin
    rst <= '1';
    wait for 20 ns;
    rst <= '0';
    wait for 20 ns;

    -- Load input memory
    while not endfile(f_in) loop
      wait until rising_edge(clk);
      readline(f_in, L_in);
      read(L_in, t_sys);
      read(L_in, t_p1);
      read(L_in, t_p2);
      
      in_valid <= '1';
      in_idx <= to_unsigned(i, G_ADDR_W);
      l_sys_in <= to_signed(t_sys, 5);
      l_par1_in <= to_signed(t_p1, 5);
      l_par2_in <= to_signed(t_p2, 5);
      i := i + 1;
      
      if i = to_integer(k_len) then
        exit;
      end if;
    end loop;
    
    wait until rising_edge(clk);
    in_valid <= '0';
    wait for 20 ns;

    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    wait until done = '1';
    wait for 100 ns;
    std.env.stop;
  end process;

  -- Trap the outputs as they fly out
  process(clk)
    file fd : text open write_mode is "tb_turbo_top_io_trace.txt";
    variable L : line;
    variable val : integer;
    variable logic_idx : integer;
    variable hard_bit : integer;
  begin
    if rising_edge(clk) then
      if out_valid = '1' then
        for i in 0 to G_P-1 loop
           logic_idx := to_integer(out_idx((i+1)*G_ADDR_W-1 downto i*G_ADDR_W)) * G_P + i;
           val := to_integer(signed(l_post((i+1)*7-1 downto i*7)));
           if val >= 0 then
              hard_bit := 0;
           else
              hard_bit := 1;
           end if;
           
           -- Write according to expected Python regex: 
           -- OUT seq idx pass bit_int bit_orig_pi l_sys l_par1 l_par2 l_post hard  
           write(L, string'("OUT 0 "));
           write(L, logic_idx);
           write(L, string'(" 8 0 0 0 0 0 "));
           write(L, val);
           write(L, string'(" "));
           write(L, hard_bit);
           writeline(fd, L);
        end loop;
      end if;
    end if;
  end process;

end architecture;
