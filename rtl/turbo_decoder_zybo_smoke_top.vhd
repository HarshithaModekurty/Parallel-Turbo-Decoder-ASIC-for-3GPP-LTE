library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;
use work.fpga_smoke_vectors_pkg.all;

entity turbo_decoder_zybo_smoke_top is
  port (
    sysclk : in std_logic;
    btn    : in std_logic_vector(1 downto 0);
    led    : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of turbo_decoder_zybo_smoke_top is
  constant C_ADDR_W : natural := 13;

  type state_t is (
    ST_IDLE,
    ST_LOAD,
    ST_START,
    ST_WAIT_DONE,
    ST_HOLD_DONE
  );

  signal st : state_t := ST_IDLE;
  signal btn_start_d : std_logic := '0';
  signal start_req_q : std_logic := '0';
  signal done_seen_q : std_logic := '0';

  signal in_valid_q : std_logic := '0';
  signal start_q : std_logic := '0';
  signal in_idx_q : unsigned(C_ADDR_W-1 downto 0) := (others => '0');
  signal l_sys_q, l_par1_q, l_par2_q : chan_llr_t := (others => '0');

  signal out_valid_q : std_logic := '0';
  signal out_idx_q : unsigned(C_ADDR_W-1 downto 0) := (others => '0');
  signal l_post_q : post_llr_t := (others => '0');
  signal done_q : std_logic := '0';

  signal load_idx_q : integer range 0 to C_FPGA_VEC_K := 0;
  signal out_count_q : integer range 0 to C_FPGA_VEC_K := 0;
begin
  dut : entity work.turbo_decoder_top
    generic map (
      G_K_MAX => C_FPGA_VEC_K,
      G_ADDR_W => C_ADDR_W
    )
    port map (
      clk => sysclk,
      rst => btn(0),
      start => start_q,
      n_half_iter => to_unsigned(C_FPGA_VEC_HALF_ITER, 5),
      k_len => to_unsigned(C_FPGA_VEC_K, C_ADDR_W),
      f1 => to_unsigned(C_FPGA_VEC_F1, C_ADDR_W),
      f2 => to_unsigned(C_FPGA_VEC_F2, C_ADDR_W),
      in_valid => in_valid_q,
      in_idx => in_idx_q,
      l_sys_in => l_sys_q,
      l_par1_in => l_par1_q,
      l_par2_in => l_par2_q,
      out_valid => out_valid_q,
      out_idx => out_idx_q,
      l_post => l_post_q,
      done => done_q
    );

  process(sysclk)
  begin
    if rising_edge(sysclk) then
      if btn(0) = '1' then
        st <= ST_IDLE;
        btn_start_d <= '0';
        start_req_q <= '0';
        done_seen_q <= '0';
        in_valid_q <= '0';
        start_q <= '0';
        in_idx_q <= (others => '0');
        l_sys_q <= (others => '0');
        l_par1_q <= (others => '0');
        l_par2_q <= (others => '0');
        load_idx_q <= 0;
        out_count_q <= 0;
      else
        btn_start_d <= btn(1);
        if btn(1) = '1' and btn_start_d = '0' then
          start_req_q <= '1';
        end if;

        in_valid_q <= '0';
        start_q <= '0';

        if out_valid_q = '1' then
          if out_count_q < C_FPGA_VEC_K then
            out_count_q <= out_count_q + 1;
          end if;
        end if;

        case st is
          when ST_IDLE =>
            done_seen_q <= '0';
            if start_req_q = '1' then
              start_req_q <= '0';
              load_idx_q <= 0;
              out_count_q <= 0;
              st <= ST_LOAD;
            end if;

          when ST_LOAD =>
            in_valid_q <= '1';
            in_idx_q <= to_unsigned(load_idx_q, C_ADDR_W);
            l_sys_q <= C_FPGA_L_SYS(load_idx_q);
            l_par1_q <= C_FPGA_L_PAR1(load_idx_q);
            l_par2_q <= C_FPGA_L_PAR2(load_idx_q);
            if load_idx_q = C_FPGA_VEC_K - 1 then
              st <= ST_START;
            else
              load_idx_q <= load_idx_q + 1;
            end if;

          when ST_START =>
            start_q <= '1';
            st <= ST_WAIT_DONE;

          when ST_WAIT_DONE =>
            if done_q = '1' then
              done_seen_q <= '1';
              st <= ST_HOLD_DONE;
            end if;

          when ST_HOLD_DONE =>
            if start_req_q = '1' then
              start_req_q <= '0';
              load_idx_q <= 0;
              out_count_q <= 0;
              done_seen_q <= '0';
              st <= ST_LOAD;
            end if;

          when others =>
            st <= ST_IDLE;
        end case;
      end if;
    end if;
  end process;

  led(0) <= '1' when st = ST_LOAD else '0';
  led(1) <= '1' when st = ST_WAIT_DONE else '0';
  led(2) <= done_seen_q;
  led(3) <= '1' when out_count_q = C_FPGA_VEC_K else '0';
end architecture;
