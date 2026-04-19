-- =============================================================================
-- File       : btb.vhd
-- Project    : IITB-RISC 2-way Superscalar Branch Predictor
-- Module     : Branch Target Buffer (BTB) with 2-bit Saturating Counters
-- Pipeline   : IF -> ID -> Schedule -> Dispatch -> Execute -> Commit -> Retire
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
--     "00" -> Strongly Not Taken  \  counter MSB = 0 -> predict NOT TAKEN
--     "01" -> Weakly   Not Taken  /
--     "10" -> Weakly   Taken      \  counter MSB = 1 -> predict TAKEN
--     "11" -> Strongly Taken      /
--
--   Initialised to "10" (Weakly Taken) on reset.
--
-- DUAL UPDATE PORTS
-- =================
--   A 2-wide superscalar commits up to two instructions per cycle. If both
--   happen to be branches or jumps, both must train the BTB in the same cycle.
--   A single update port would silently drop one of them. Two independent
--   update ports (upd0, upd1) solve this. Each port is completely independent:
--   separate enable, PC, taken flag, and target. The update process handles
--   them sequentially within the same clock edge. If both ports write to the
--   same BTB index (i.e. both branch PCs hash to the same entry), upd1 wins
--   because it is applied second — this is an acceptable conflict policy for a
--   direct-mapped BTB.
--
-- WHICH INSTRUCTIONS TRAIN THE BTB
-- ==================================
--   Only branch and jump instructions train the BTB. The commit stage must
--   gate update_en for each slot accordingly:
--
--     Instruction        update_en   update_taken    Notes
--     ─────────────────────────────────────────────────────────────────────
--     BEQ / BLT / BLE    always      actual outcome  Even not-taken updates
--                                                     the counter so it can
--                                                     converge to not-taken.
--                                                     Only write a NEW entry
--                                                     if the branch was taken
--                                                     (no point predicting a
--                                                     not-taken branch that
--                                                     has never been seen as
--                                                     taken). See policy below.
--     JAL                always      '1'             Unconditional.
--     JLR                always      '1'             Unconditional.
--     JRI                always      '1'             Unconditional.
--     All others         never       —               ALU, load, store: PC
--                                                     is always sequential.
--
--   NOT-TAKEN ENTRY CREATION POLICY:
--     If update_taken = '0' AND the entry for this PC does not already exist
--     in the BTB (valid='0' or tag mismatch), do NOT create a new entry.
--     There is no point storing a target for a branch that has only ever been
--     seen as not-taken — it would waste a BTB slot and the target field would
--     be meaningless (we'd store PC+4 which is never needed from a BTB).
--     If the entry DOES already exist (was previously taken), decrement the
--     counter so the predictor can learn not-taken over time.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity btb is
    generic (
        NUM_ENTRIES : integer := 16;
        INDEX_BITS  : integer := 4;
        TAG_BITS    : integer := 11;
        ADDR_WIDTH  : integer := 16
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- -----------------------------------------------------------------
        -- Lookup port (combinational, IF stage)
        -- -----------------------------------------------------------------
        lookup_pc   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        hit         : out std_logic;
        pred_taken  : out std_logic;
        pred_target : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- -----------------------------------------------------------------
        -- Update port 0 — commit slot 0 (sequential, commit stage)
        -- Set upd0_en only for branch/jump instructions, never for others.
        -- -----------------------------------------------------------------
        upd0_en     : in std_logic;
        upd0_pc     : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        upd0_taken  : in std_logic;
        upd0_target : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- -----------------------------------------------------------------
        -- Update port 1 — commit slot 1 (sequential, commit stage)
        -- Same rules as upd0. Both ports may fire in the same cycle.
        -- If both map to the same BTB index, upd1 wins (applied second).
        -- -----------------------------------------------------------------
        upd1_en     : in std_logic;
        upd1_pc     : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        upd1_taken  : in std_logic;
        upd1_target : in std_logic_vector(ADDR_WIDTH-1 downto 0)
    );
end entity btb;

architecture rtl of btb is

    type btb_entry_t is record
        valid   : std_logic;
        tag     : std_logic_vector(TAG_BITS-1 downto 0);
        target  : std_logic_vector(ADDR_WIDTH-1 downto 0);
        counter : std_logic_vector(1 downto 0);
    end record;

    constant BTB_ENTRY_INIT : btb_entry_t := (
        valid   => '0',
        tag     => (others => '0'),
        target  => (others => '0'),
        counter => "10"
    );

    type btb_array_t is array(0 to NUM_ENTRIES-1) of btb_entry_t;
    signal btb_mem : btb_array_t := (others => BTB_ENTRY_INIT);

    -- -----------------------------------------------------------------------
    -- Helpers
    -- -----------------------------------------------------------------------
    function get_index(pc : std_logic_vector) return integer is
    begin
        return to_integer(unsigned(pc(INDEX_BITS downto 1)));
    end function;

    function get_tag(pc : std_logic_vector) return std_logic_vector is
    begin
        return pc(ADDR_WIDTH-1 downto INDEX_BITS+1);
    end function;

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

    -- Apply one update to an entry variable and return the result.
    -- Encapsulates the not-taken entry creation policy so both update
    -- ports share identical logic.
    procedure apply_update (
        signal   mem   : in  btb_array_t;
        variable entry : out btb_entry_t;
        constant idx   : in  integer;
        constant tag   : in  std_logic_vector(TAG_BITS-1 downto 0);
        constant taken : in  std_logic;
        constant tgt   : in  std_logic_vector(ADDR_WIDTH-1 downto 0)
    ) is
        variable e : btb_entry_t;
    begin
        e := mem(idx);

        if taken = '1' then
            -- Taken: always write/update the entry (creates it if new).
            e.valid   := '1';
            e.tag     := tag;
            e.target  := tgt;
            e.counter := sat_inc(e.counter);
        else
            -- Not-taken: only update if the entry already exists for this PC.
            -- Do NOT create a new entry just because a branch wasn't taken.
            if e.valid = '1' and e.tag = tag then
                e.counter := sat_dec(e.counter);
                -- Keep existing target — useful if branch oscillates.
            end if;
            -- If entry doesn't exist: do nothing (no new entry for not-taken).
        end if;

        entry := e;
    end procedure;

begin

    -- =========================================================================
    -- Lookup (combinational, IF stage)
    -- =========================================================================
    process(btb_mem, lookup_pc)
        variable idx   : integer;
        variable entry : btb_entry_t;
    begin
        idx   := get_index(lookup_pc);
        entry := btb_mem(idx);

        if entry.valid = '1' and entry.tag = get_tag(lookup_pc) then
            hit         <= '1';
            pred_taken  <= entry.counter(1);
            pred_target <= entry.target;
        else
            hit         <= '0';
            pred_taken  <= '0';
            pred_target <= (others => '0');
        end if;
    end process;

    -- =========================================================================
    -- Dual update (sequential, commit stage)
    --
    -- upd0 is applied first, then upd1 on top of whatever upd0 wrote.
    -- If both target the same index, upd1 wins. This is intentional —
    -- in program order slot 1 is the younger instruction, so its outcome
    -- is the more recent training signal.
    -- =========================================================================
    process(clk, rst)
        variable idx0, idx1 : integer;
        variable entry0, entry1 : btb_entry_t;
    begin
        if rst = '1' then
            btb_mem <= (others => BTB_ENTRY_INIT);

        elsif rising_edge(clk) then

            -- Apply upd0
            if upd0_en = '1' then
                idx0 := get_index(upd0_pc);
                apply_update(btb_mem, entry0, idx0,
                             get_tag(upd0_pc), upd0_taken, upd0_target);
                btb_mem(idx0) <= entry0;
            end if;

            -- Apply upd1 (on top of upd0 if same index — upd1 wins)
            if upd1_en = '1' then
                idx1 := get_index(upd1_pc);
                apply_update(btb_mem, entry1, idx1,
                             get_tag(upd1_pc), upd1_taken, upd1_target);
                btb_mem(idx1) <= entry1;
            end if;

        end if;
    end process;

end architecture rtl;
