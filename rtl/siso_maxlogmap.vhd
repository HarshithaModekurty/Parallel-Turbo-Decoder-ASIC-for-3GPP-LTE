library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity siso_maxlogmap is
  generic (
    G_K_MAX  : natural := 6144;
    G_ADDR_W : natural := 13;
    G_W      : natural := 30; -- Window size in Radix-4 stages
    G_L      : natural := 16  -- Learning length in Radix-4 stages
  );
  port (
    clk, rst  : in std_logic;
    start     : in std_logic;
    k_len     : in unsigned(G_ADDR_W-1 downto 0);
    in_valid  : in std_logic;
    in_idx    : in unsigned(G_ADDR_W-1 downto 0);
    sys0      : in llr_t;
    sys1      : in llr_t;
    par0      : in llr_t;
    par1      : in llr_t;
    apri0     : in ext_llr_t;
    apri1     : in ext_llr_t;
    out_valid : out std_logic;
    out_idx   : out unsigned(G_ADDR_W-1 downto 0);
    ext0      : out ext_llr_t;
    ext1      : out ext_llr_t;
    done      : out std_logic
  );
end entity;

architecture rtl of siso_maxlogmap is

  -- Sliding window dimensions
  constant DEPTH_W : natural := G_W + G_L;
  
  -- Shift registers for inputs
  type llr_array_t is array (0 to DEPTH_W-1) of llr_t;
  type ext_llr_array_t is array (0 to DEPTH_W-1) of ext_llr_t;
  signal sys0_sr, sys1_sr, par0_sr, par1_sr : llr_array_t;
  signal apr0_sr, apr1_sr : ext_llr_array_t;
  
  -- Shift register for forward metrics
  type state_metric_array_t is array (0 to DEPTH_W-1) of state_metric_t;
  signal alpha_sr : state_metric_array_t;
  
  -- Signals for pipelined processing
  signal alpha_cur : state_metric_t;
  signal beta_learn, beta_decode : state_metric_t;
  
  -- BMU outputs
  signal gam_fwd, gam_learn, gam_decode : metric_vec_t(0 to 15);
  
  -- State machine
  type state_t is (IDLE, FILL_WINDOW, RUN_WINDOW, DRAIN, FINISH);
  signal st : state_t := IDLE;
  
  signal count_fwd, count_out : natural range 0 to G_K_MAX-1;
  signal wait_learn : natural range 0 to G_L-1;
  signal k_len_pairs : natural;
  
begin

  -- FWD BMU
  u_bmu_fwd: entity work.radix4_bmu
    port map (
      clk   => clk,
      rst   => rst,
      sys0  => sys0, sys1 => sys1,
      par0  => par0, par1 => par1,
      apri0 => apri0, apri1 => apri1,
      gamma => gam_fwd
    );

  -- FWD ACS
  u_acs_fwd: entity work.radix4_acs
    port map (
      state_in  => alpha_cur,
      gamma_in  => gam_fwd,
      mode_bwd  => '0',
      state_out => alpha_sr(0)
    );

  -- LEARN BMU
  u_bmu_ln: entity work.radix4_bmu
    port map (
      clk   => clk,
      rst   => rst,
      sys0  => sys0_sr(G_W-1), sys1 => sys1_sr(G_W-1),
      par0  => par0_sr(G_W-1), par1 => par1_sr(G_W-1),
      apri0 => apr0_sr(G_W-1), apri1 => apr1_sr(G_W-1),
      gamma => gam_learn
    );

  -- LEARN ACS
  u_acs_ln: entity work.radix4_acs
    port map (
      state_in  => beta_learn,
      gamma_in  => gam_learn,
      mode_bwd  => '1',
      state_out => beta_learn
    );

  -- DCD BMU
  u_bmu_dcd: entity work.radix4_bmu
    port map (
      clk   => clk,
      rst   => rst,
      sys0  => sys0_sr(DEPTH_W-1), sys1 => sys1_sr(DEPTH_W-1),
      par0  => par0_sr(DEPTH_W-1), par1 => par1_sr(DEPTH_W-1),
      apri0 => apr0_sr(DEPTH_W-1), apri1 => apr1_sr(DEPTH_W-1),
      gamma => gam_decode
    );

  -- DCD ACS
  u_acs_dcd: entity work.radix4_acs
    port map (
      state_in  => beta_decode,
      gamma_in  => gam_decode,
      mode_bwd  => '1',
      state_out => beta_decode
    );

  -- Output extraction logic
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st <= IDLE;
        out_valid <= '0';
        done <= '0';
        for s in 0 to C_NUM_STATES-1 loop
           if s = 0 then alpha_cur(s) <= (others=>'0');
           else alpha_cur(s) <= to_signed(-512, metric_t'length); end if;
        end loop;
      else
        out_valid <= '0';
        done <= '0';
        
        if in_valid = '1' then
           sys0_sr <= sys0 & sys0_sr(0 to sys0_sr'high-1);
           sys1_sr <= sys1 & sys1_sr(0 to sys1_sr'high-1);
           par0_sr <= par0 & par0_sr(0 to par0_sr'high-1);
           par1_sr <= par1 & par1_sr(0 to par1_sr'high-1);
           apr0_sr <= apri0 & apr0_sr(0 to apr0_sr'high-1);
           apr1_sr <= apri1 & apr1_sr(0 to apr1_sr'high-1);
           alpha_sr <= alpha_sr(0 to alpha_sr'high-1);
           alpha_cur <= alpha_sr(0);
        end if;
        
        case st is
           when IDLE =>
              if start = '1' then
                 k_len_pairs <= to_integer(k_len) / 2;
                 st <= FILL_WINDOW;
              end if;
           when FILL_WINDOW =>
              if in_valid = '1' then
                 out_valid <= '1';
                 ext0 <= (others => '0');
                 ext1 <= (others => '0');
                 if count_fwd = k_len_pairs - 1 then
                    st <= FINISH;
                    done <= '1';
                 end if;
              end if;
           when others =>
              st <= IDLE;
        end case;
      end if;
    end if;
  end process;

end architecture;

