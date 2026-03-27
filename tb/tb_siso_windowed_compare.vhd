library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;
use std.env.all;

entity tb_siso_windowed_compare is
end entity;

architecture sim of tb_siso_windowed_compare is
  type int_vec32_t is array (0 to 31) of integer;
  signal clk, rst, start, in_valid, out_valid, done : std_logic := '0';
  signal seg_first_s, seg_last_s : std_logic := '0';
  signal seg_len, in_pair_idx, out_pair_idx : unsigned(12 downto 0) := (others => '0');
  signal sys_e, sys_o, par_e, par_o : chan_llr_t := (others => '0');
  signal apr_e, apr_o, ext_e, ext_o : ext_llr_t := (others => '0');
  signal post_e, post_o : post_llr_t := (others => '0');
begin
  dut: entity work.siso_maxlogmap
    generic map (G_SEG_MAX => 64, G_ADDR_W => 13)
    port map(
      clk => clk,
      rst => rst,
      start => start,
      seg_first => seg_first_s,
      seg_last => seg_last_s,
      seg_len => seg_len,
      in_valid => in_valid,
      in_pair_idx => in_pair_idx,
      sys_even => sys_e,
      sys_odd => sys_o,
      par_even => par_e,
      par_odd => par_o,
      apri_even => apr_e,
      apri_odd => apr_o,
      fetch_req_valid => open,
      fetch_req_pair_idx => open,
      fetch_rsp_valid => '0',
      out_valid => out_valid,
      out_pair_idx => out_pair_idx,
      ext_even => ext_e,
      ext_odd => ext_o,
      post_even => post_e,
      post_odd => post_o,
      done => done
    );

  clk <= not clk after 5 ns;

  process
    constant C_SEG_LEN : natural := 32;
    variable sys_mem, par_mem : int_vec32_t := (others => 0);
    variable ext_obs, post_obs : int_vec32_t := (others => 0);
    variable out_cnt : integer;

    procedure init_patterns is
    begin
      for n in 0 to 15 loop
        sys_mem(2*n) := (n mod 7) - 3;
        sys_mem(2*n + 1) := ((n + 2) mod 7) - 3;
        par_mem(2*n) := (n mod 5) - 2;
        par_mem(2*n + 1) := ((n + 1) mod 5) - 2;
      end loop;
    end procedure;

    procedure load_segment(first_i : std_logic; last_i : std_logic) is
    begin
      seg_first_s <= first_i;
      seg_last_s <= last_i;
      seg_len <= to_unsigned(C_SEG_LEN, seg_len'length);

      wait until rising_edge(clk);
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';

      for pair in 0 to (C_SEG_LEN / 2) - 1 loop
        in_valid <= '1';
        in_pair_idx <= to_unsigned(pair, in_pair_idx'length);
        sys_e <= sat_chan(sys_mem(2*pair));
        sys_o <= sat_chan(sys_mem(2*pair + 1));
        par_e <= sat_chan(par_mem(2*pair));
        par_o <= sat_chan(par_mem(2*pair + 1));
        apr_e <= to_signed(0, ext_llr_t'length);
        apr_o <= to_signed(0, ext_llr_t'length);
        wait until rising_edge(clk);
      end loop;
      in_valid <= '0';
    end procedure;

    procedure collect_outputs is
      variable pair_i : integer;
    begin
      out_cnt := 0;
      ext_obs := (others => 0);
      post_obs := (others => 0);
      for cyc in 0 to 4000 loop
        wait until rising_edge(clk);
        if out_valid = '1' then
          pair_i := to_integer(out_pair_idx);
          ext_obs(2*pair_i) := to_integer(ext_e);
          ext_obs(2*pair_i + 1) := to_integer(ext_o);
          post_obs(2*pair_i) := to_integer(post_e);
          post_obs(2*pair_i + 1) := to_integer(post_o);
          out_cnt := out_cnt + 1;
        end if;
        exit when done = '1';
      end loop;
      assert done = '1' report "SISO did not assert done" severity error;
      assert out_cnt = 16 report "Expected 16 pair outputs, got " & integer'image(out_cnt) severity error;
    end procedure;

    procedure check_case(
      name_i : string;
      first_i : std_logic;
      last_i  : std_logic;
      exp_ext : int_vec32_t;
      exp_post : int_vec32_t
    ) is
    begin
      load_segment(first_i, last_i);
      collect_outputs;
      for i in 0 to C_SEG_LEN-1 loop
        assert ext_obs(i) = exp_ext(i)
          report name_i & " ext mismatch at bit " & integer'image(i) &
                 ": exp=" & integer'image(exp_ext(i)) & " got=" & integer'image(ext_obs(i))
          severity error;
        assert post_obs(i) = exp_post(i)
          report name_i & " post mismatch at bit " & integer'image(i) &
                 ": exp=" & integer'image(exp_post(i)) & " got=" & integer'image(post_obs(i))
          severity error;
      end loop;
    end procedure;

    constant ext_11 : int_vec32_t := (4, 2, 1, 0, 2, -1, 0, -3, -1, -4, -4, 4, -4, 2, 4, 0, 3, -1, 1, -2, 0, -3, 0, -5, -3, 4, -5, 2, 4, 1, 4, -2);
    constant post_11 : int_vec32_t := (4, 2, 0, 0, 2, 0, 1, -1, 0, -2, -3, 3, -2, 2, 4, 0, 3, -1, 1, -1, 1, -1, 1, -3, -2, 3, -3, 2, 3, 1, 4, -2);
    constant ext_10 : int_vec32_t := (4, 2, 1, 0, 2, -1, 0, -3, -1, -4, -4, 4, -4, 2, 4, 0, 3, -1, 1, -2, 0, -3, 0, -5, -3, 4, -5, 2, 4, 1, 1, 0);
    constant post_10 : int_vec32_t := (4, 2, 0, 0, 2, 0, 1, -1, 0, -2, -3, 3, -2, 2, 4, 0, 3, -1, 1, -1, 1, -1, 1, -3, -2, 3, -3, 2, 3, 1, 0, 1);
    constant ext_00 : int_vec32_t := (4, 0, 1, 0, 0, -1, 0, -3, -1, -4, -3, 4, -4, 2, 4, 0, 3, -1, 1, -2, 0, -3, 0, -5, -3, 4, -5, 2, 4, 1, 1, 0);
    constant post_00 : int_vec32_t := (3, 0, 0, 0, 0, 0, 0, -1, 0, -2, -1, 3, -2, 2, 4, 0, 3, -1, 1, -1, 1, -1, 1, -3, -2, 3, -3, 2, 3, 1, 0, 1);
    constant ext_01 : int_vec32_t := (4, 0, 1, 0, 0, -1, 0, -3, -1, -4, -3, 4, -4, 2, 4, 0, 3, -1, 1, -2, 0, -3, 0, -5, -3, 4, -5, 2, 4, 1, 4, -2);
    constant post_01 : int_vec32_t := (3, 0, 0, 0, 0, 0, 0, -1, 0, -2, -1, 3, -2, 2, 4, 0, 3, -1, 1, -1, 1, -1, 1, -3, -2, 3, -3, 2, 3, 1, 4, -2);
  begin
    init_patterns;

    rst <= '1';
    wait for 20 ns;
    rst <= '0';

    check_case("seg11", '1', '1', ext_11, post_11);
    check_case("seg10", '1', '0', ext_10, post_10);
    check_case("seg00", '0', '0', ext_00, post_00);
    check_case("seg01", '0', '1', ext_01, post_01);

    report "tb_siso_windowed_compare passed" severity note;
    finish;
  end process;
end architecture;
