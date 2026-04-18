-- =============================================================================
-- cdb_wakeup.vhd
-- Common Data Bus (CDB) Broadcast & RS Wakeup for IITB-RISC Superscalar
--
-- When any Execution Unit (ADD, NAND, Load/Store) completes, it places its
-- result tag and value on the CDB.  This unit:
--   1. Broadcasts (tag, value) to every Reservation Station entry.
--   2. Compares the broadcast tag against each entry's OPR1/OPR2 tag fields.
--   3. On a match, writes the value into the operand slot and sets Valid=1.
--   4. The Scheduler sees the entry as "ready" on the very next cycle.
--
-- This is the core of Tomasulo's algorithm.
--
-- RS entry layout (RS_DEPTH = 32, matching your design):
--   busy          : 1  bit
--   control       : 7  bits  (opcode 4 + complement 1 + condition 2)
--   opr1          : 16 bits  – value or tag
--   valid1        : 1  bit   – '1' = opr1 holds a real value
--   opr2          : 16 bits  – value or tag
--   valid2        : 1  bit   – '1' = opr2 holds a real value
--   ready         : 1  bit   – both operands valid (scheduler uses this)
--   dest_tag      : 5  bits  – RRF tag for the destination register
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cdb_pkg is
    constant RS_DEPTH    : integer := 32;
    constant TAG_BITS    : integer := 5;   -- 32 RRF entries → 5-bit tag
    constant DATA_BITS   : integer := 16;
    constant CTRL_BITS   : integer := 7;

    -- A single RS entry as a record (easier to work with than a flat bus)
    type rs_entry_t is record
        busy     : std_logic;
        control  : std_logic_vector(CTRL_BITS-1  downto 0);
        opr1     : std_logic_vector(DATA_BITS-1  downto 0);
        valid1   : std_logic;
        opr2     : std_logic_vector(DATA_BITS-1  downto 0);
        valid2   : std_logic;
        ready    : std_logic;
        dest_tag : std_logic_vector(TAG_BITS-1   downto 0);
    end record;

    type rs_array_t is array (0 to RS_DEPTH-1) of rs_entry_t;
end package cdb_pkg;

-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdb_pkg.all;

entity cdb_wakeup is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;

        -- -----------------------------------------------------------------
        -- CDB inputs – up to 3 EUs can write per cycle (ADD, NAND, LD/ST).
        -- A valid bit gates each bus.
        -- -----------------------------------------------------------------
        cdb0_valid  : in  std_logic;
        cdb0_tag    : in  std_logic_vector(TAG_BITS-1  downto 0);
        cdb0_value  : in  std_logic_vector(DATA_BITS-1 downto 0);

        cdb1_valid  : in  std_logic;
        cdb1_tag    : in  std_logic_vector(TAG_BITS-1  downto 0);
        cdb1_value  : in  std_logic_vector(DATA_BITS-1 downto 0);

        cdb2_valid  : in  std_logic;
        cdb2_tag    : in  std_logic_vector(TAG_BITS-1  downto 0);
        cdb2_value  : in  std_logic_vector(DATA_BITS-1 downto 0);

        -- -----------------------------------------------------------------
        -- RS array – driven by the dispatch / flush logic elsewhere.
        -- This unit reads all entries and writes back updated operands.
        -- -----------------------------------------------------------------
        rs_in       : in  rs_array_t;   -- current RS state
        rs_out      : out rs_array_t;   -- RS state after CDB capture

        -- -----------------------------------------------------------------
        -- RRF write-back (same cycle, forwarded to register file)
        -- -----------------------------------------------------------------
        rrf_wr0_en  : out std_logic;
        rrf_wr0_tag : out std_logic_vector(TAG_BITS-1  downto 0);
        rrf_wr0_val : out std_logic_vector(DATA_BITS-1 downto 0);

        rrf_wr1_en  : out std_logic;
        rrf_wr1_tag : out std_logic_vector(TAG_BITS-1  downto 0);
        rrf_wr1_val : out std_logic_vector(DATA_BITS-1 downto 0);

        rrf_wr2_en  : out std_logic;
        rrf_wr2_tag : out std_logic_vector(TAG_BITS-1  downto 0);
        rrf_wr2_val : out std_logic_vector(DATA_BITS-1 downto 0)
    );
end entity cdb_wakeup;

architecture rtl of cdb_wakeup is

    -- Helper: apply one CDB broadcast to one RS entry (combinational)
    procedure apply_cdb (
        signal   entry    : inout rs_entry_t;
        constant c_valid  : in    std_logic;
        constant c_tag    : in    std_logic_vector(TAG_BITS-1  downto 0);
        constant c_value  : in    std_logic_vector(DATA_BITS-1 downto 0)
    ) is begin
        if c_valid = '1' and entry.busy = '1' then
            -- OPR1 capture
            if entry.valid1 = '0' and
               entry.opr1(TAG_BITS-1 downto 0) = c_tag then
                entry.opr1   <= c_value;
                entry.valid1 <= '1';
            end if;
            -- OPR2 capture
            if entry.valid2 = '0' and
               entry.opr2(TAG_BITS-1 downto 0) = c_tag then
                entry.opr2   <= c_value;
                entry.valid2 <= '1';
            end if;
        end if;
    end procedure;

begin

    -- ------------------------------------------------------------------
    -- Combinational wakeup logic
    -- All three CDB buses are checked against every RS entry in parallel.
    -- The updated RS array is driven to rs_out immediately (registered
    -- downstream in the RS file).
    -- ------------------------------------------------------------------
    WAKEUP: process(rs_in,
                    cdb0_valid, cdb0_tag, cdb0_value,
                    cdb1_valid, cdb1_tag, cdb1_value,
                    cdb2_valid, cdb2_tag, cdb2_value)
        variable tmp : rs_array_t;
    begin
        tmp := rs_in;   -- start from current state

        for i in 0 to RS_DEPTH-1 loop
            -- Apply CDB0
            if cdb0_valid = '1' and tmp(i).busy = '1' then
                if tmp(i).valid1 = '0' and
                   tmp(i).opr1(TAG_BITS-1 downto 0) = cdb0_tag then
                    tmp(i).opr1   := cdb0_value;
                    tmp(i).valid1 := '1';
                end if;
                if tmp(i).valid2 = '0' and
                   tmp(i).opr2(TAG_BITS-1 downto 0) = cdb0_tag then
                    tmp(i).opr2   := cdb0_value;
                    tmp(i).valid2 := '1';
                end if;
            end if;

            -- Apply CDB1
            if cdb1_valid = '1' and tmp(i).busy = '1' then
                if tmp(i).valid1 = '0' and
                   tmp(i).opr1(TAG_BITS-1 downto 0) = cdb1_tag then
                    tmp(i).opr1   := cdb1_value;
                    tmp(i).valid1 := '1';
                end if;
                if tmp(i).valid2 = '0' and
                   tmp(i).opr2(TAG_BITS-1 downto 0) = cdb1_tag then
                    tmp(i).opr2   := cdb1_value;
                    tmp(i).valid2 := '1';
                end if;
            end if;

            -- Apply CDB2
            if cdb2_valid = '1' and tmp(i).busy = '1' then
                if tmp(i).valid1 = '0' and
                   tmp(i).opr1(TAG_BITS-1 downto 0) = cdb2_tag then
                    tmp(i).opr1   := cdb2_value;
                    tmp(i).valid1 := '1';
                end if;
                if tmp(i).valid2 = '0' and
                   tmp(i).opr2(TAG_BITS-1 downto 0) = cdb2_tag then
                    tmp(i).opr2   := cdb2_value;
                    tmp(i).valid2 := '1';
                end if;
            end if;

            -- Update ready bit: both operands now valid
            if tmp(i).valid1 = '1' and tmp(i).valid2 = '1' then
                tmp(i).ready := '1';
            end if;
        end loop;

        rs_out <= tmp;
    end process WAKEUP;

    -- ------------------------------------------------------------------
    -- RRF write-back: route each CDB broadcast straight to the RRF so
    -- the architectural register file stays consistent for commit.
    -- ------------------------------------------------------------------
    rrf_wr0_en  <= cdb0_valid;
    rrf_wr0_tag <= cdb0_tag;
    rrf_wr0_val <= cdb0_value;

    rrf_wr1_en  <= cdb1_valid;
    rrf_wr1_tag <= cdb1_tag;
    rrf_wr1_val <= cdb1_value;

    rrf_wr2_en  <= cdb2_valid;
    rrf_wr2_tag <= cdb2_tag;
    rrf_wr2_val <= cdb2_value;

end architecture rtl;
