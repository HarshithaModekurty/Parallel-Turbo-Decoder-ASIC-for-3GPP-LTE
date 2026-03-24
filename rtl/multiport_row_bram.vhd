library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

entity multiport_row_bram is
  generic (
    G_ROWS   : natural := 384;
    G_ADDR_W : natural := 13;
    G_BANKS  : natural := 16;
    G_LANES  : natural := C_PARALLEL;
    G_WORD_W : natural := ext_llr_t'length
  );
  port (
    clk         : in  std_logic;
    rd_en       : in  std_logic;
    rd_addr     : in  unsigned(G_ADDR_W-1 downto 0);
    rd_data     : out signed(G_LANES*G_WORD_W-1 downto 0);
    wr0_en      : in  std_logic;
    wr0_addr    : in  unsigned(G_ADDR_W-1 downto 0);
    wr0_lane_we : in  std_logic_vector(0 to G_LANES-1);
    wr0_data    : in  signed(G_LANES*G_WORD_W-1 downto 0);
    wr1_en      : in  std_logic;
    wr1_addr    : in  unsigned(G_ADDR_W-1 downto 0);
    wr1_lane_we : in  std_logic_vector(0 to G_LANES-1);
    wr1_data    : in  signed(G_LANES*G_WORD_W-1 downto 0)
  );
end entity;

architecture rtl of multiport_row_bram is
  constant C_BYTE_W    : natural := 8;
  constant C_PACK_W    : natural := G_LANES * C_BYTE_W;
  constant C_BANK_ROWS : natural := (G_ROWS + G_BANKS - 1) / G_BANKS;

  subtype bank_word_t is std_logic_vector(C_PACK_W-1 downto 0);
  type bank_ram_t is array (0 to C_BANK_ROWS-1) of bank_word_t;
  type bank_word_arr_t is array (0 to G_BANKS-1) of bank_word_t;

  signal bank_q     : bank_word_arr_t := (others => (others => '0'));
  signal rd_bank_q  : natural range 0 to G_BANKS-1 := 0;
  signal rd_valid_q : std_logic := '0';

  function lane_to_byte(
    row_v  : signed(G_LANES*G_WORD_W-1 downto 0);
    lane_i : natural
  ) return std_logic_vector is
    variable ret : signed(C_BYTE_W-1 downto 0) := (others => '0');
  begin
    ret := resize(row_v((lane_i+1)*G_WORD_W-1 downto lane_i*G_WORD_W), C_BYTE_W);
    return std_logic_vector(ret);
  end function;

  function bank_to_row(word_v : bank_word_t) return signed is
    variable ret : signed(G_LANES*G_WORD_W-1 downto 0) := (others => '0');
    variable byte_v : signed(C_BYTE_W-1 downto 0) := (others => '0');
  begin
    for lane in 0 to G_LANES-1 loop
      byte_v := signed(word_v((lane+1)*C_BYTE_W-1 downto lane*C_BYTE_W));
      ret((lane+1)*G_WORD_W-1 downto lane*G_WORD_W) := byte_v(G_WORD_W-1 downto 0);
    end loop;
    return ret;
  end function;
begin
  process(clk)
    variable rd_addr_i : integer;
  begin
    if rising_edge(clk) then
      rd_addr_i := to_integer(rd_addr);
      if rd_en = '1' and rd_addr_i >= 0 and rd_addr_i < G_ROWS then
        rd_bank_q <= rd_addr_i mod G_BANKS;
        rd_valid_q <= '1';
      else
        rd_bank_q <= 0;
        rd_valid_q <= '0';
      end if;
    end if;
  end process;

  gen_bank : for bank in 0 to G_BANKS-1 generate
    signal mem : bank_ram_t := (others => (others => '0'));
    attribute ram_style : string;
    attribute ram_style of mem : signal is "block";
  begin
    process(clk)
      variable rd_addr_i  : integer;
      variable wr0_addr_i : integer;
      variable wr1_addr_i : integer;
      variable rd_local_i : integer;
      variable wr0_local_i : integer;
      variable wr1_local_i : integer;
      variable wr0_hit : boolean;
      variable wr1_hit : boolean;
      variable row_v : bank_word_t;
    begin
      if rising_edge(clk) then
        rd_addr_i := to_integer(rd_addr);
        wr0_addr_i := to_integer(wr0_addr);
        wr1_addr_i := to_integer(wr1_addr);
        rd_local_i := 0;
        wr0_local_i := 0;
        wr1_local_i := 0;

        wr0_hit := false;
        wr1_hit := false;

        if wr0_en = '1' and wr0_addr_i >= 0 and wr0_addr_i < G_ROWS then
          wr0_local_i := wr0_addr_i / G_BANKS;
          wr0_hit := (wr0_addr_i mod G_BANKS) = bank and wr0_local_i < C_BANK_ROWS;
        end if;

        if wr1_en = '1' and wr1_addr_i >= 0 and wr1_addr_i < G_ROWS then
          wr1_local_i := wr1_addr_i / G_BANKS;
          wr1_hit := (wr1_addr_i mod G_BANKS) = bank and wr1_local_i < C_BANK_ROWS;
        end if;

        assert not (wr0_hit and wr1_hit)
          report "multiport_row_bram received two writes to the same bank in one cycle"
          severity failure;

        if wr0_hit then
          row_v := mem(wr0_local_i);
          for lane in 0 to G_LANES-1 loop
            if wr0_lane_we(lane) = '1' then
              row_v((lane+1)*C_BYTE_W-1 downto lane*C_BYTE_W) := lane_to_byte(wr0_data, lane);
            end if;
          end loop;
          mem(wr0_local_i) <= row_v;
        elsif wr1_hit then
          row_v := mem(wr1_local_i);
          for lane in 0 to G_LANES-1 loop
            if wr1_lane_we(lane) = '1' then
              row_v((lane+1)*C_BYTE_W-1 downto lane*C_BYTE_W) := lane_to_byte(wr1_data, lane);
            end if;
          end loop;
          mem(wr1_local_i) <= row_v;
        end if;

        if rd_en = '1' and rd_addr_i >= 0 and rd_addr_i < G_ROWS then
          rd_local_i := rd_addr_i / G_BANKS;
          if (rd_addr_i mod G_BANKS) = bank and rd_local_i < C_BANK_ROWS then
            bank_q(bank) <= mem(rd_local_i);
          else
            bank_q(bank) <= (others => '0');
          end if;
        else
          bank_q(bank) <= (others => '0');
        end if;
      end if;
    end process;
  end generate;

  process(all)
  begin
    if rd_valid_q = '1' then
      rd_data <= bank_to_row(bank_q(rd_bank_q));
    else
      rd_data <= (others => '0');
    end if;
  end process;
end architecture;
