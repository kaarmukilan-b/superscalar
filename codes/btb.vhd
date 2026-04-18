-- =============================================================================
-- File       : btb.vhd
-- Project    : IITB-RISC 2-way Superscalar Branch Predictor
-- Module     : Branch Target Buffer (BTB) with 2-bit Saturating Counters
-- Pipeline   : IF -> ID -> Schedule -> Dispatch -> Execute -> Commit -> Retire
-- Author     : EE739 Group
-- -----------------------------------------------------------------------------
-- Description:
--   Direct-mapped BTB with 16 entries. Each entry stores a valid bit, tag,
--   branch target address, and a 2-bit saturating counter for prediction.
--
--   PC Breakdown (16-bit, word-aligned so bit-0 is always 0):
--     Bit 0       : always 0 (ignored)
--     Bits [4:1]  : INDEX (4 bits -> 16 entries)
--     Bits [15:5] : TAG   (11 bits)
--
--   2-bit counter states:
--     "00" -> Strongly Not Taken
--     "01" -> Weakly Not Taken   } predict NOT TAKEN (counter MSB = 0)
--     "10" -> Weakly Taken       } predict TAKEN     (counter MSB = 1)
--     "11" -> Strongly Taken
--
--   Initialised to "10" (Weakly Taken) on reset.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity btb is
    generic (
        NUM_ENTRIES : integer := 16;   -- Number of BTB entries (power of 2)
        INDEX_BITS  : integer := 4;    -- log2(NUM_ENTRIES)
        TAG_BITS    : integer := 11;   -- ADDR_WIDTH - INDEX_BITS - 1
        ADDR_WIDTH  : integer := 16    -- IITB-RISC is 16-bit
    );
    port (
        clk  : in std_logic;
        rst  : in std_logic;

        -- -----------------------------------------------------------------
        -- Lookup Port  (used combinationally in IF stage)
        -- -----------------------------------------------------------------
        lookup_pc   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        hit         : out std_logic;   -- '1' if BTB entry found for lookup_pc
        pred_taken  : out std_logic;   -- '1' if counter MSB = 1 (predict taken)
        pred_target : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- -----------------------------------------------------------------
        -- Update Port  (driven from Execute stage after branch resolves)
        -- -----------------------------------------------------------------
        update_en     : in std_logic;
        update_pc     : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        update_taken  : in std_logic;  -- actual outcome
        update_target : in std_logic_vector(ADDR_WIDTH-1 downto 0)
    );
end entity btb;

architecture rtl of btb is

    -- -------------------------------------------------------------------------
    -- BTB Entry Record
    -- -------------------------------------------------------------------------
    type btb_entry_t is record
        valid   : std_logic;
        tag     : std_logic_vector(TAG_BITS-1 downto 0);
        target  : std_logic_vector(ADDR_WIDTH-1 downto 0);
        counter : std_logic_vector(1 downto 0);
    end record;

    -- Initialise all entries to invalid, counter = "10" (weakly taken)
    constant BTB_ENTRY_INIT : btb_entry_t := (
        valid   => '0',
        tag     => (others => '0'),
        target  => (others => '0'),
        counter => "10"
    );

    type btb_array_t is array(0 to NUM_ENTRIES-1) of btb_entry_t;
    signal btb_mem : btb_array_t := (others => BTB_ENTRY_INIT);

    -- -------------------------------------------------------------------------
    -- Helper: extract index and tag from a PC
    -- PC[0] is always 0 (word aligned), index = PC[INDEX_BITS:1]
    -- -------------------------------------------------------------------------
    function get_index(pc : std_logic_vector) return integer is
    begin
        return to_integer(unsigned(pc(INDEX_BITS downto 1)));
    end function;

    function get_tag(pc : std_logic_vector) return std_logic_vector is
    begin
        return pc(ADDR_WIDTH-1 downto INDEX_BITS+1);
    end function;

    -- -------------------------------------------------------------------------
    -- Helper: 2-bit saturating increment / decrement
    -- -------------------------------------------------------------------------
    function sat_inc(cnt : std_logic_vector(1 downto 0)) return std_logic_vector is
    begin
        if cnt = "11" then return "11";
        else return std_logic_vector(unsigned(cnt) + 1);
        end if;
    end function;

    function sat_dec(cnt : std_logic_vector(1 downto 0)) return std_logic_vector is
    begin
        if cnt = "00" then return "00";
        else return std_logic_vector(unsigned(cnt) - 1);
        end if;
    end function;

begin

    -- =========================================================================
    -- Lookup Logic  (purely combinational, read happens in IF stage)
    -- =========================================================================
    process(btb_mem, lookup_pc)
        variable idx   : integer;
        variable entry : btb_entry_t;
    begin
        idx   := get_index(lookup_pc);
        entry := btb_mem(idx);

        if entry.valid = '1' and entry.tag = get_tag(lookup_pc) then
            hit         <= '1';
            pred_taken  <= entry.counter(1);   -- MSB: 1 -> taken, 0 -> not taken
            pred_target <= entry.target;
        else
            hit         <= '0';
            pred_taken  <= '0';
            pred_target <= (others => '0');
        end if;
    end process;

    -- =========================================================================
    -- Update Logic  (sequential, driven from Execute stage)
    -- =========================================================================
    process(clk, rst)
        variable idx   : integer;
        variable entry : btb_entry_t;
    begin
        if rst = '1' then
            btb_mem <= (others => BTB_ENTRY_INIT);

        elsif rising_edge(clk) then
            if update_en = '1' then
                idx   := get_index(update_pc);
                entry := btb_mem(idx);

                -- Always update tag and target (handles conflict misses too)
                entry.valid  := '1';
                entry.tag    := get_tag(update_pc);
                entry.target := update_target;

                -- Saturate counter based on actual outcome
                if update_taken = '1' then
                    entry.counter := sat_inc(entry.counter);
                else
                    entry.counter := sat_dec(entry.counter);
                end if;

                btb_mem(idx) <= entry;
            end if;
        end if;
    end process;

end architecture rtl;
