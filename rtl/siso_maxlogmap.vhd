library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity siso_maxlogmap is
  generic (
    G_K_MAX : natural := 6144;
    G_ADDR_W : natural := 13
  );
  port (
    clk, rst : in std_logic;
    start    : in std_logic;
    k_len    : in unsigned(G_ADDR_W-1 downto 0);
    in_valid : in std_logic;
    in_idx   : in unsigned(G_ADDR_W-1 downto 0);
    l_sys    : in llr_t;
    l_par    : in llr_t;
    l_apri   : in llr_t;
    out_valid : out std_logic;
    out_idx   : out unsigned(G_ADDR_W-1 downto 0);
    l_ext     : out llr_t;
    done      : out std_logic
  );
end entity;

architecture rtl of siso_maxlogmap is
  type alpha_mem_t is array (0 to G_K_MAX-1) of state_metric_t;
  type llr_mem_t is array (0 to G_K_MAX-1) of llr_t;
  signal alpha_mem : alpha_mem_t;
  signal sys_mem, par_mem, apr_mem : llr_mem_t;

  type state_t is (IDLE, FWD_LOAD, BWD_RUN, FINISH);
  signal st : state_t;

  signal alpha_cur, alpha_nxt, beta_cur : state_metric_t;
  signal idx_fwd, idx_bwd : integer range 0 to G_K_MAX-1;
  signal k_i : integer range 0 to G_K_MAX;
  signal v_o, done_o : std_logic;
  signal ext_o : llr_t;
  signal idx_o : unsigned(G_ADDR_W-1 downto 0);

  function bm_for_transition(prev_state : natural; u : std_logic; ls, lp, la : llr_t) return metric_t is
    variable p : std_logic;
    variable g0,g1,g2,g3 : metric_t;
  begin
    p := rsc_parity(prev_state, u);
    g0 := shift_right(sat_add(sat_add(resize_llr_to_metric(ls), resize_llr_to_metric(la)), resize_llr_to_metric(lp)), 1);
    g1 := shift_right(sat_add(sat_add(resize_llr_to_metric(ls), resize_llr_to_metric(la)), -resize_llr_to_metric(lp)), 1);
    g2 := shift_right(sat_add(sat_add(-resize_llr_to_metric(ls), -resize_llr_to_metric(la)), resize_llr_to_metric(lp)), 1);
    g3 := shift_right(sat_add(sat_add(-resize_llr_to_metric(ls), -resize_llr_to_metric(la)), -resize_llr_to_metric(lp)), 1);
    if u='0' and p='0' then return g0;
    elsif u='0' and p='1' then return g1;
    elsif u='1' and p='0' then return g2;
    else return g3;
    end if;
  end function;

begin
  process(clk)
    variable new_alpha, new_beta : state_metric_t;
    variable m0,m1 : metric_t;
    variable prev0,prev1 : natural;
    variable denorm : metric_t;
    variable sum0,sum1,max0,max1 : metric_t;
  begin
    if rising_edge(clk) then
      if rst='1' then
        st <= IDLE;
        idx_fwd <= 0;
        idx_bwd <= 0;
        k_i <= 0;
        v_o <= '0';
        done_o <= '0';
      else
        v_o <= '0';
        done_o <= '0';
        case st is
          when IDLE =>
            if start='1' then
              k_i <= to_integer(k_len);
              for s in 0 to C_NUM_STATES-1 loop
                if s=0 then alpha_cur(s) <= (others=>'0');
                else alpha_cur(s) <= to_signed(-1024, metric_t'length); end if;
              end loop;
              idx_fwd <= 0;
              st <= FWD_LOAD;
            end if;

          when FWD_LOAD =>
            if in_valid='1' then
              sys_mem(idx_fwd) <= l_sys;
              par_mem(idx_fwd) <= l_par;
              apr_mem(idx_fwd) <= l_apri;

              for s in 0 to C_NUM_STATES-1 loop
                m0 := to_signed(-1024, metric_t'length);
                m1 := to_signed(-1024, metric_t'length);
                for p in 0 to C_NUM_STATES-1 loop
                  if rsc_next_state(p,'0') = s then
                    m0 := max2(m0, sat_add(alpha_cur(p), bm_for_transition(p,'0',l_sys,l_par,l_apri)));
                  end if;
                  if rsc_next_state(p,'1') = s then
                    m1 := max2(m1, sat_add(alpha_cur(p), bm_for_transition(p,'1',l_sys,l_par,l_apri)));
                  end if;
                end loop;
                new_alpha(s) := max2(m0,m1);
              end loop;
              denorm := max8(new_alpha);
              for s in 0 to C_NUM_STATES-1 loop
                alpha_cur(s) <= new_alpha(s) - denorm;
              end loop;
              alpha_mem(idx_fwd) <= new_alpha;

              if idx_fwd = k_i-1 then
                for s in 0 to C_NUM_STATES-1 loop
                  if s=0 then beta_cur(s) <= (others=>'0');
                  else beta_cur(s) <= to_signed(-1024, metric_t'length); end if;
                end loop;
                idx_bwd <= k_i-1;
                st <= BWD_RUN;
              else
                idx_fwd <= idx_fwd + 1;
              end if;
            end if;

          when BWD_RUN =>
            for s in 0 to C_NUM_STATES-1 loop
              new_beta(s) := to_signed(-1024, metric_t'length);
              prev0 := rsc_next_state(s, '0');
              new_beta(s) := max2(new_beta(s), sat_add(beta_cur(prev0), bm_for_transition(s,'0',sys_mem(idx_bwd),par_mem(idx_bwd),apr_mem(idx_bwd))));
              prev1 := rsc_next_state(s, '1');
              new_beta(s) := max2(new_beta(s), sat_add(beta_cur(prev1), bm_for_transition(s,'1',sys_mem(idx_bwd),par_mem(idx_bwd),apr_mem(idx_bwd))));
            end loop;

            max0 := to_signed(-1024, metric_t'length);
            max1 := to_signed(-1024, metric_t'length);
            for p in 0 to C_NUM_STATES-1 loop
              sum0 := sat_add(alpha_mem(idx_bwd)(p), sat_add(bm_for_transition(p,'0',sys_mem(idx_bwd),par_mem(idx_bwd),apr_mem(idx_bwd)), new_beta(rsc_next_state(p,'0'))));
              sum1 := sat_add(alpha_mem(idx_bwd)(p), sat_add(bm_for_transition(p,'1',sys_mem(idx_bwd),par_mem(idx_bwd),apr_mem(idx_bwd)), new_beta(rsc_next_state(p,'1'))));
              max0 := max2(max0, sum0);
              max1 := max2(max1, sum1);
            end loop;
            ext_o <= resize((max1 - max0) - resize_llr_to_metric(sys_mem(idx_bwd)) - resize_llr_to_metric(apr_mem(idx_bwd)), llr_t'length);
            idx_o <= to_unsigned(idx_bwd, G_ADDR_W);
            v_o <= '1';

            denorm := max8(new_beta);
            for s in 0 to C_NUM_STATES-1 loop
              beta_cur(s) <= new_beta(s) - denorm;
            end loop;

            if idx_bwd = 0 then
              st <= FINISH;
            else
              idx_bwd <= idx_bwd - 1;
            end if;

          when FINISH =>
            done_o <= '1';
            st <= IDLE;

          when others => st <= IDLE;
        end case;
      end if;
    end if;
  end process;

  out_valid <= v_o;
  out_idx <= idx_o;
  l_ext <= ext_o;
  done <= done_o;
end architecture;
