library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity radix4_extractor is
  port (
    clk       : in std_logic;
    alpha_in  : in state_metric_t;
    beta_in   : in state_metric_t;
    gamma_in  : in metric_vec_t(0 to 15);
    sys0_in   : in llr_t;
    apri0_in  : in ext_llr_t;
    sys1_in   : in llr_t;
    apri1_in  : in ext_llr_t;
    ext0_out  : out ext_llr_t;
    ext1_out  : out ext_llr_t
  );
end entity;

architecture rtl of radix4_extractor is

  type r4_path_t is record
    start_idx : natural;
    gamma_idx : natural;
    end_idx   : natural;
    u0_bit    : natural;
    u1_bit    : natural;
  end record;
  type path_array_t is array (0 to 31) of r4_path_t;

  function build_paths return path_array_t is
    variable t : path_array_t;
    variable idx : natural := 0;
    variable mid_s, nxt_s : natural;
    variable p0, p1 : std_logic;
    variable g_idx, p0_bit, p1_bit : natural;
  begin
    for start_s in 0 to 7 loop
      for u0 in 0 to 1 loop
        for u1 in 0 to 1 loop
          if u0 = 1 then p0 := rsc_parity(start_s, '1'); mid_s := rsc_next_state(start_s, '1');
          else p0 := rsc_parity(start_s, '0'); mid_s := rsc_next_state(start_s, '0'); end if;
          
          if u1 = 1 then p1 := rsc_parity(mid_s, '1'); nxt_s := rsc_next_state(mid_s, '1');
          else p1 := rsc_parity(mid_s, '0'); nxt_s := rsc_next_state(mid_s, '0'); end if;
          
          if p0 = '1' then p0_bit := 1; else p0_bit := 0; end if;
          if p1 = '1' then p1_bit := 1; else p1_bit := 0; end if;
          g_idx := (u0 * 8) + (p0_bit * 4) + (u1 * 2) + p1_bit;
          
          t(idx).start_idx := start_s;
          t(idx).gamma_idx := g_idx;
          t(idx).end_idx := nxt_s;
          t(idx).u0_bit := u0;
          t(idx).u1_bit := u1;
          idx := idx + 1;
        end loop;
      end loop;
    end loop;
    return t;
  end function;

  constant P_MAP : path_array_t := build_paths;
  
  function m_max(a, b : metric_t) return metric_t is
  begin
    return mod_max(a, b);
  end function;

begin
  process(clk)
    variable p_metric : metric_vec_t(0 to 31);
    
    variable m0_u0, m0_u1 : metric_t;
    variable m1_u0, m1_u1 : metric_t;
    
    variable init0_0, init0_1, init1_0, init1_1 : boolean;
    
    variable l_post0, l_post1 : metric_t;
    variable e0, e1 : metric_t;
    
    variable sys_ext0, apri_ext0 : metric_t;
    variable sys_ext1, apri_ext1 : metric_t;
  begin
    if rising_edge(clk) then
      -- Stage 1: Add Alpha + Gamma + Beta
      for i in 0 to 31 loop
        p_metric(i) := mod_add(mod_add(alpha_in(P_MAP(i).start_idx), gamma_in(P_MAP(i).gamma_idx)), beta_in(P_MAP(i).end_idx));
      end loop;
      
      init0_0 := true; init0_1 := true; init1_0 := true; init1_1 := true;
      m0_u0 := (others=>'0'); m1_u0 := (others=>'0');
      m0_u1 := (others=>'0'); m1_u1 := (others=>'0');
      
      -- Stage 2: Max finders
      for i in 0 to 31 loop
        if P_MAP(i).u0_bit = 0 then
          if init0_0 then m0_u0 := p_metric(i); init0_0 := false; else m0_u0 := m_max(m0_u0, p_metric(i)); end if;
        else
          if init1_0 then m1_u0 := p_metric(i); init1_0 := false; else m1_u0 := m_max(m1_u0, p_metric(i)); end if;
        end if;
        
        if P_MAP(i).u1_bit = 0 then
          if init0_1 then m0_u1 := p_metric(i); init0_1 := false; else m0_u1 := m_max(m0_u1, p_metric(i)); end if;
        else
          if init1_1 then m1_u1 := p_metric(i); init1_1 := false; else m1_u1 := m_max(m1_u1, p_metric(i)); end if;
        end if;
      end loop;
      
      -- L Post = M1 - M0 (modulo arithmetic wraps nicely)
      l_post0 := m1_u0 - m0_u0;
      l_post1 := m1_u1 - m0_u1;
      
      sys_ext0 := resize(sys0_in, metric_t'length);
      apri_ext0 := resize(apri0_in, metric_t'length);
      
      sys_ext1 := resize(sys1_in, metric_t'length);
      apri_ext1 := resize(apri1_in, metric_t'length);
      
      -- Extrinsic = L_Post - Sys - Apri
      e0 := l_post0 - sys_ext0 - apri_ext0;
      e1 := l_post1 - sys_ext1 - apri_ext1;
      
      -- Saturation to ext_llr_t'length
      if e0 > 31 then e0 := to_signed(31, metric_t'length); 
      elsif e0 < -32 then e0 := to_signed(-32, metric_t'length); end if;
      
      if e1 > 31 then e1 := to_signed(31, metric_t'length); 
      elsif e1 < -32 then e1 := to_signed(-32, metric_t'length); end if;

      ext0_out <= resize(e0, ext_llr_t'length);
      ext1_out <= resize(e1, ext_llr_t'length);
    end if;
  end process;

end architecture;
