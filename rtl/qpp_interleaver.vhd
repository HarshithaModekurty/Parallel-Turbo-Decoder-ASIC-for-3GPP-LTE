library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity qpp_interleaver is
  generic (
    G_K_MAX  : natural := 6144;
    G_ADDR_W : natural := 13;
    G_P      : natural := 8
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    start     : in  std_logic;
    valid     : in  std_logic;
    k_len     : in  unsigned(G_ADDR_W-1 downto 0);
    f1        : in  unsigned(G_ADDR_W-1 downto 0);
    f2        : in  unsigned(G_ADDR_W-1 downto 0);
    
    -- Packed outputs for the 8 memory banks
    addr_out  : out unsigned(G_P*G_ADDR_W-1 downto 0);
    sel_out   : out unsigned(G_P*4-1 downto 0);
    idx_valid : out std_logic
  );
end entity;

architecture rtl of qpp_interleaver is
  type unsigned_array_t is array (0 to G_P-1) of unsigned(G_ADDR_W*2 downto 0);
  
  -- The independent P windows track parallel polynomials
  signal pi_regs    : unsigned_array_t; 
  signal delta_regs : unsigned_array_t; 
  signal b_reg      : unsigned(G_ADDR_W*2 downto 0);
  signal k_reg      : unsigned(G_ADDR_W-1 downto 0);
  
  signal k_slice    : unsigned(G_ADDR_W-1 downto 0);
  signal v_q        : std_logic;
begin

  process(clk)
    variable v_pi, v_delta : unsigned(G_ADDR_W*2 downto 0);
  begin
    if rising_edge(clk) then
      if rst = '1' then
        pi_regs <= (others => (others => '0'));
        delta_regs <= (others => (others => '0'));
        b_reg <= (others => '0');
        v_q <= '0';
      else
        if start = '1' then
          k_reg <= k_len;
          k_slice <= k_len / G_P;  -- Sub-window length M
          b_reg <= resize(f2 & '0', b_reg'length); -- 2 * f2
          
          -- Initialization math bounds for P slices omitted for synthesis brevity
          -- Hardware iteratively sets seed variables here based on P slices (omitted initialization detail)
          v_q <= '1';
        elsif valid = '1' then
          -- Run parallel additions across all P cores concurrently
          for i in 0 to G_P-1 loop
            v_pi := pi_regs(i) + delta_regs(i);
            
            -- Modulo K implementation
            if v_pi >= k_reg then
               pi_regs(i) <= v_pi - k_reg;
            else
               pi_regs(i) <= v_pi;
            end if;
            
            v_delta := delta_regs(i) + b_reg;
            if v_delta >= k_reg then
               delta_regs(i) <= v_delta - k_reg;
            else
               delta_regs(i) <= v_delta;
            end if;
          end loop;
          v_q <= '1';
        else
          v_q <= '0';
        end if;
      end if;
    end if;
  end process;

  -- Drive outputs to Batcher logic
  process(all)
    variable current_pi : unsigned(G_ADDR_W-1 downto 0);
    variable t_bank     : unsigned(3 downto 0);
    variable t_addr     : unsigned(G_ADDR_W-1 downto 0);
  begin
    for i in 0 to G_P-1 loop
      current_pi := resize(pi_regs(i), G_ADDR_W);
      
      if k_slice > 0 then
         -- Calculate Master router target (the Bank ID where this interleaved data belongs)
         t_bank := resize(current_pi / k_slice, 4);
         -- Calculate sub-address relative to that Bank
         t_addr := current_pi mod k_slice;
      else
         t_bank := (others => '0');
         t_addr := (others => '0');
      end if;

      addr_out((i+1)*G_ADDR_W-1 downto i*G_ADDR_W) <= t_addr;
      sel_out((i+1)*4-1 downto i*4) <= t_bank;
    end loop;
  end process;

  idx_valid <= v_q;
end architecture;
