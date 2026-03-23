library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity qpp_interleaver is
  generic (
    G_K_MAX : natural := 6144;
    G_ADDR_W : natural := 13
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    start     : in  std_logic;
    valid     : in  std_logic;
    k_len     : in  unsigned(G_ADDR_W-1 downto 0);
    f1        : in  unsigned(G_ADDR_W-1 downto 0);
    f2        : in  unsigned(G_ADDR_W-1 downto 0);
    idx_o     : out unsigned(G_ADDR_W-1 downto 0);
    idx_valid : out std_logic
  );
end entity;

architecture rtl of qpp_interleaver is
  signal pi_reg    : unsigned(G_ADDR_W downto 0) := (others => '0');
  signal delta_reg : unsigned(G_ADDR_W downto 0) := (others => '0');
  signal b_reg     : unsigned(G_ADDR_W downto 0) := (others => '0');
  signal k_reg     : unsigned(G_ADDR_W downto 0) := (others => '0');
  signal v_q       : std_logic := '0';
begin
  process(clk)
    variable sum_pi : unsigned(G_ADDR_W downto 0);
    variable sum_delta : unsigned(G_ADDR_W downto 0);
    variable sum_f1f2 : unsigned(G_ADDR_W downto 0);
    variable sum_f2f2 : unsigned(G_ADDR_W downto 0);
    variable k_v : unsigned(G_ADDR_W downto 0);
    variable f1_v : unsigned(G_ADDR_W downto 0);
    variable f2_v : unsigned(G_ADDR_W downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        pi_reg <= (others => '0');
        delta_reg <= (others => '0');
        b_reg <= (others => '0');
        k_reg <= (others => '0');
        v_q <= '0';
      else
        if start = '1' then
          k_v := resize(k_len, G_ADDR_W + 1);
          f1_v := resize(f1, G_ADDR_W + 1);
          f2_v := resize(f2, G_ADDR_W + 1);

          k_reg <= k_v;
          pi_reg <= (others => '0');

          sum_f1f2 := f1_v + f2_v;
          if (k_v /= 0) and (sum_f1f2 >= k_v) then
            delta_reg <= sum_f1f2 - k_v;
          else
            delta_reg <= sum_f1f2;
          end if;

          sum_f2f2 := f2_v + f2_v;
          if (k_v /= 0) and (sum_f2f2 >= k_v) then
            b_reg <= sum_f2f2 - k_v;
          else
            b_reg <= sum_f2f2;
          end if;

          v_q <= '1';
        elsif valid = '1' then
          sum_pi := pi_reg + delta_reg;
          if (k_reg /= 0) and (sum_pi >= k_reg) then
            pi_reg <= sum_pi - k_reg;
          else
            pi_reg <= sum_pi;
          end if;

          sum_delta := delta_reg + b_reg;
          if (k_reg /= 0) and (sum_delta >= k_reg) then
            delta_reg <= sum_delta - k_reg;
          else
            delta_reg <= sum_delta;
          end if;

          v_q <= '1';
        else
          v_q <= '0';
        end if;
      end if;
    end if;
  end process;

  idx_o <= resize(pi_reg, G_ADDR_W);
  idx_valid <= v_q;
end architecture;
