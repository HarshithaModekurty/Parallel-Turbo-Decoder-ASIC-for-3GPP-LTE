library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity radix4_bmu is
  port (
    clk     : in std_logic;
    rst     : in std_logic;
    
    sys0  : in llr_t;
    par0  : in llr_t;
    apri0 : in ext_llr_t;
    
    sys1  : in llr_t;
    par1  : in llr_t;
    apri1 : in ext_llr_t;
    
    gamma : out metric_vec_t(0 to 15)
  );
end entity;

architecture rtl of radix4_bmu is
  signal s_sys0, s_par0, s_ap0 : metric_t;
  signal s_sys1, s_par1, s_ap1 : metric_t;
  
  -- Pre-processing Pipeline Registers
  signal sys_ap_sum0, sys_ap_sum1 : metric_t;
  signal p_par0, p_par1           : metric_t;
  
  type g_step_t is array(0 to 3) of metric_t;
  signal g0, g1 : g_step_t;
begin

  s_sys0 <= resize(sys0, metric_t'length);
  s_par0 <= resize(par0, metric_t'length);
  s_ap0  <= resize(apri0, metric_t'length);
  
  s_sys1 <= resize(sys1, metric_t'length);
  s_par1 <= resize(par1, metric_t'length);
  s_ap1  <= resize(apri1, metric_t'length);

  -- Stage 1: Branch Metric Pre-Processing (Systematic + A-priori merge)
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sys_ap_sum0 <= (others => '0');
        sys_ap_sum1 <= (others => '0');
        p_par0 <= (others => '0');
        p_par1 <= (others => '0');
      else
        sys_ap_sum0 <= mod_add(s_sys0, s_ap0);
        sys_ap_sum1 <= mod_add(s_sys1, s_ap1);
        p_par0 <= s_par0; -- delay parity to match pipeline
        p_par1 <= s_par1;
      end if;
    end if;
  end process;

  -- Stage 2: Parity distribution 
  g0(0) <= shift_right(mod_add( sys_ap_sum0, p_par0), 1);
  g0(1) <= shift_right(mod_add( sys_ap_sum0, -p_par0), 1);
  g0(2) <= shift_right(mod_add(-sys_ap_sum0, p_par0), 1);
  g0(3) <= shift_right(mod_add(-sys_ap_sum0, -p_par0), 1);

  g1(0) <= shift_right(mod_add( sys_ap_sum1, p_par1), 1);
  g1(1) <= shift_right(mod_add( sys_ap_sum1, -p_par1), 1);
  g1(2) <= shift_right(mod_add(-sys_ap_sum1, p_par1), 1);
  g1(3) <= shift_right(mod_add(-sys_ap_sum1, -p_par1), 1);

  -- 16-state combinational mapping
  process(all)
    variable g0_idx, g1_idx : natural;
  begin
    for u0 in 0 to 1 loop
      for p0 in 0 to 1 loop
        for u1 in 0 to 1 loop
          for p1 in 0 to 1 loop
            g0_idx := u0 * 2 + p0;
            g1_idx := u1 * 2 + p1;
            gamma((u0*8) + (p0*4) + (u1*2) + p1) <= mod_add(g0(g0_idx), g1(g1_idx));
          end loop;
        end loop;
      end loop;
    end loop;
  end process;
end architecture;
