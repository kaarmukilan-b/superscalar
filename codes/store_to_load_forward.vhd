-- =============================================================================
-- store_to_load_forward.vhd
-- Store-to-Load Forwarding Unit for IITB-RISC Superscalar Processor
--
-- When the Load/Store EU computes a load address, this unit checks every
-- valid (uncommitted) store-buffer entry.  If a younger-than-commit store
-- has the same 16-bit byte address, its data is forwarded directly to the
-- load result register, bypassing the cache/memory entirely.
--
-- Store Buffer entry layout (STORE_BUF_DEPTH = 16 entries):
--   valid    : 1  bit  – entry is occupied
--   complete : 1  bit  – address AND data are both known (not just dispatched)
--   address  : 16 bits – byte address computed by the store EU
--   data     : 16 bits – value to be written
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity store_to_load_forward is
    generic (
        STORE_BUF_DEPTH : integer := 16   -- number of store-buffer slots
    );
    port (
        -- ---------------------------------------------------------------
        -- Load address presented by the Load/Store EU (cycle 1 of 2)
        -- ---------------------------------------------------------------
        load_addr       : in  std_logic_vector(15 downto 0);
        load_addr_valid : in  std_logic;   -- '1' when address is stable

        -- ---------------------------------------------------------------
        -- Store buffer snapshot (driven by the store-buffer register file)
        -- ---------------------------------------------------------------
        sb_valid        : in  std_logic_vector(STORE_BUF_DEPTH-1 downto 0);
        sb_complete     : in  std_logic_vector(STORE_BUF_DEPTH-1 downto 0);
        sb_addr         : in  std_logic_vector(STORE_BUF_DEPTH*16-1 downto 0);
        sb_data         : in  std_logic_vector(STORE_BUF_DEPTH*16-1 downto 0);

        -- ---------------------------------------------------------------
        -- Forwarding result
        -- ---------------------------------------------------------------
        fwd_hit         : out std_logic;                      -- match found
        fwd_data        : out std_logic_vector(15 downto 0);  -- forwarded value

        -- ---------------------------------------------------------------
        -- Stall signal: a store to this address exists but its data is
        -- not yet known (address computed, data still in-flight).
        -- The load must wait rather than read stale memory.
        -- ---------------------------------------------------------------
        fwd_stall       : out std_logic
    );
end entity store_to_load_forward;

architecture rtl of store_to_load_forward is

    -- Unpack the flat bus into arrays for readability
    type addr_array_t is array (0 to STORE_BUF_DEPTH-1) of
                         std_logic_vector(15 downto 0);
    type data_array_t is array (0 to STORE_BUF_DEPTH-1) of
                         std_logic_vector(15 downto 0);

    signal sb_addr_arr : addr_array_t;
    signal sb_data_arr : data_array_t;

    -- Internal hit/stall vectors (one bit per store-buffer entry)
    signal hit_vec   : std_logic_vector(STORE_BUF_DEPTH-1 downto 0);
    signal stall_vec : std_logic_vector(STORE_BUF_DEPTH-1 downto 0);

    -- Index of the youngest (highest-index) hit — simple priority encoder
    -- In a real out-of-order design you would use ROB order; here we use
    -- the store-buffer index as a proxy (newest entries at higher indices
    -- if the buffer is managed as a circular FIFO with a known tail).
    signal fwd_idx   : integer range 0 to STORE_BUF_DEPTH-1 := 0;
    signal any_hit   : std_logic := '0';
    signal any_stall : std_logic := '0';

begin

    -- ------------------------------------------------------------------
    -- Unpack flat buses into arrays
    -- ------------------------------------------------------------------
    UNPACK: for i in 0 to STORE_BUF_DEPTH-1 generate
        sb_addr_arr(i) <= sb_addr((i+1)*16-1 downto i*16);
        sb_data_arr(i) <= sb_data((i+1)*16-1 downto i*16);
    end generate;

    -- ------------------------------------------------------------------
    -- Per-entry match logic
    -- ------------------------------------------------------------------
    MATCH: for i in 0 to STORE_BUF_DEPTH-1 generate
        -- hit  : entry occupied, address known, address matches
        hit_vec(i) <= sb_valid(i) and sb_complete(i)
                      and load_addr_valid
                      and '1' when (sb_addr_arr(i) = load_addr) else '0';

        -- stall: entry occupied, address matches, but data not yet known
        stall_vec(i) <= sb_valid(i) and (not sb_complete(i))
                        and load_addr_valid
                        and '1' when (sb_addr_arr(i) = load_addr) else '0';
    end generate;

    -- ------------------------------------------------------------------
    -- Priority encoder: pick the LAST (youngest) hit entry.
    -- Iterating from high to low index gives us the most-recent store.
    -- ------------------------------------------------------------------
    PRIORITY: process(hit_vec, stall_vec, sb_data_arr)
        variable found     : std_logic := '0';
        variable found_idx : integer   := 0;
        variable stall_or  : std_logic := '0';
    begin
        found     := '0';
        found_idx := 0;
        stall_or  := '0';

        for i in STORE_BUF_DEPTH-1 downto 0 loop
            if stall_vec(i) = '1' then
                stall_or := '1';
            end if;
            if hit_vec(i) = '1' and found = '0' then
                found     := '1';
                found_idx := i;
            end if;
        end loop;

        any_hit   <= found;
        fwd_idx   <= found_idx;
        any_stall <= stall_or;
    end process PRIORITY;

    -- ------------------------------------------------------------------
    -- Drive outputs
    -- ------------------------------------------------------------------
    fwd_hit   <= any_hit;
    fwd_stall <= any_stall and (not any_hit);
    -- (if we have a full hit we can forward; stall only when we have an
    --  address match but the store data is not yet computed)

    fwd_data  <= sb_data_arr(fwd_idx) when any_hit = '1'
                 else (others => '0');

end architecture rtl;
