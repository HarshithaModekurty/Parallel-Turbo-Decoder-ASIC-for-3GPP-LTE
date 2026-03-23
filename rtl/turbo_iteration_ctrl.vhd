library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity turbo_iteration_ctrl is
  generic (
    G_MAX_HALF_ITER : natural := 31
  );
  port (
    clk, rst : in std_logic;
    start : in std_logic;
    n_half_iter : in unsigned(4 downto 0);
    siso_done_1 : in std_logic;
    siso_done_2 : in std_logic;
    run_siso_1 : out std_logic;
    run_siso_2 : out std_logic;
    deint_phase : out std_logic;
    last_half : out std_logic;
    done : out std_logic
  );
end entity;

architecture rtl of turbo_iteration_ctrl is
  type st_t is (IDLE, RUN1, RUN2, FINISH);
  signal st : st_t := IDLE;
  signal half_idx : unsigned(4 downto 0) := (others => '0');
  signal done_q : std_logic := '0';

  function is_last_half(idx, total : unsigned(4 downto 0)) return boolean is
  begin
    return idx + 1 >= total;
  end function;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= IDLE;
        half_idx <= (others => '0');
        done_q <= '0';
      else
        done_q <= '0';
        case st is
          when IDLE =>
            if start = '1' then
              half_idx <= (others => '0');
              if n_half_iter = 0 then
                st <= FINISH;
              else
                st <= RUN1;
              end if;
            end if;

          when RUN1 =>
            if siso_done_1 = '1' then
              if is_last_half(half_idx, n_half_iter) then
                st <= FINISH;
              else
                half_idx <= half_idx + 1;
                st <= RUN2;
              end if;
            end if;

          when RUN2 =>
            if siso_done_2 = '1' then
              if is_last_half(half_idx, n_half_iter) then
                st <= FINISH;
              else
                half_idx <= half_idx + 1;
                st <= RUN1;
              end if;
            end if;

          when FINISH =>
            done_q <= '1';
            st <= IDLE;

          when others =>
            st <= IDLE;
        end case;
      end if;
    end if;
  end process;

  run_siso_1 <= '1' when st = RUN1 else '0';
  run_siso_2 <= '1' when st = RUN2 else '0';
  deint_phase <= '1' when st = RUN2 else '0';
  last_half <= '1' when (st = RUN1 or st = RUN2) and is_last_half(half_idx, n_half_iter) else '0';
  done <= done_q;
end architecture;
