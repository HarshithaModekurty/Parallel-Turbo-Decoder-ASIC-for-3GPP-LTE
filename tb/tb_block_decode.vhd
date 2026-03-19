library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.turbo_pkg.all;

entity tb_block_decode is
end entity;

architecture sim of tb_block_decode is
  constant C_ADDR_W : natural := 13;
  constant C_P      : natural := 8;

  signal clk, rst  : std_logic := '0';
  signal start     : std_logic := '0';
  signal n_iter    : unsigned(3 downto 0) := (others => '0');
  signal k_len     : unsigned(C_ADDR_W-1 downto 0) := (others => '0');
  signal f1, f2    : unsigned(C_ADDR_W-1 downto 0) := (others => '0');
  signal in_valid  : std_logic := '0';
  signal in_idx    : unsigned(C_ADDR_W-1 downto 0) := (others => '0');
  signal l_sys_in  : llr_t := (others => '0');
  signal l_par1_in : llr_t := (others => '0');
  signal l_par2_in : llr_t := (others => '0');
  
  signal out_valid : std_logic;
  signal out_idx   : unsigned(C_ADDR_W-1 downto 0);
  signal l_post    : llr_t;
  signal done      : std_logic;

  function clamp_llr(v : integer) return llr_t is
  begin
    if v > 15 then return to_signed(15, 5);
    elsif v < -16 then return to_signed(-16, 5);
    else return to_signed(v, 5); end if;
  end function;

begin

  uut: entity work.turbo_decoder_top
    generic map (
      G_K_MAX  => 40,
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
    file text_file : text open read_mode is "sim_vectors/lte_frame_input_vectors.txt";
    variable text_line : line;
    variable v_len, v_niter, v_f1, v_f2 : integer;
    variable v_idx, v_borig, v_bint, v_sys, v_par1, v_par2 : integer;
  begin
    rst <= '1';
    wait for 20 ns;
    rst <= '0';
    wait for 10 ns;

    -- Read Header
    readline(text_file, text_line);
    read(text_line, v_len);
    read(text_line, v_niter);
    read(text_line, v_f1);
    read(text_line, v_f2);
    
    k_len <= to_unsigned(v_len, C_ADDR_W);
    n_iter <= to_unsigned(v_niter, 4);
    f1 <= to_unsigned(v_f1, C_ADDR_W);
    f2 <= to_unsigned(v_f2, C_ADDR_W);

    wait for 10 ns;

      -- Read Vectors
      for i in 0 to v_len-1 loop
        readline(text_file, text_line);
        read(text_line, v_idx);
        read(text_line, v_borig);
        read(text_line, v_bint);
        read(text_line, v_sys);
        read(text_line, v_par1);
        read(text_line, v_par2);

        in_valid <= '1';
        in_idx <= to_unsigned(v_idx, C_ADDR_W);
        l_sys_in <= clamp_llr(v_sys);
        l_par1_in <= clamp_llr(v_par1);
        l_par2_in <= clamp_llr(v_par2);

        wait for 10 ns;
      end loop;

      in_valid <= '0';
      wait for 10 ns;
      
      start <= '1';
      wait for 10 ns;
      start <= '0';
      
    
    -- Wait for done
    wait until done = '1' for 50000 ns;
    
    report "Decoder finished computing the frame. Validation complete.";
    wait for 100 ns;
    std.env.stop;
  end process;

end architecture;
