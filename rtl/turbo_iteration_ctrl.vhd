library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity turbo_iteration_ctrl is
  generic (
    G_MAX_ITER : natural := 8
  );
  port (
    clk, rst : in std_logic;
    start : in std_logic;
    n_iter : in unsigned(3 downto 0);
    siso_done_1 : in std_logic;
    siso_done_2 : in std_logic;
    run_siso_1 : out std_logic;
    run_siso_2 : out std_logic;
    deint_phase : out std_logic;
    done : out std_logic
  );
end entity;

architecture rtl of turbo_iteration_ctrl is
  type st_t is (IDLE, RUN1, RUN2, FINISH);
  signal st : st_t;
  signal iter : unsigned(3 downto 0);
  signal r1,r2,d,phase : std_logic;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst='1' then
        st <= IDLE; iter <= (others=>'0'); r1<='0'; r2<='0'; d<='0'; phase<='0';
      else
        r1<='0'; r2<='0'; d<='0';
        case st is
          when IDLE =>
            if start='1' then
              iter <= (others=>'0');
              r1 <= '1'; -- Pulse r1 here
              st <= RUN1;
            end if;
          when RUN1 =>
            -- Do NOT assign r1<='1' here. 
            phase<='0';
            if siso_done_1='1' then 
               r2 <= '1'; -- Pulse r2 here
               st <= RUN2; 
            end if;
          when RUN2 =>
            -- Do NOT assign r2<='1' here.
            phase<='1';
            if siso_done_2='1' then
              if iter+1 >= n_iter then
                st <= FINISH;
              else
                iter <= iter+1;
                r1 <= '1'; -- Pulse r1 for the next iteration
                st <= RUN1;
              end if;
            end if;
          when FINISH =>
            d<='1';
            st <= IDLE;
          when others => st <= IDLE;
        end case;
      end if;
    end if;
  end process;
  run_siso_1 <= r1; run_siso_2 <= r2; done <= d; deint_phase <= phase;
end architecture;
