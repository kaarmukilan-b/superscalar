-- =============================================================================
-- rrf_freelist.vhd
-- RRF Free-List FIFO for IITB-RISC Superscalar Processor
--
-- This is the physical-register free-list mentioned in your notes but absent
-- from the main diagram. It is the central bookkeeping structure for register
-- renaming correctness.
--
-- OPERATIONS
-- ==========
--
-- DISPATCH (pop, up to 2 per cycle):
--   Each dispatched instruction that writes a register needs a fresh physical
--   tag.  Pop from the head of the FIFO.  The tag goes into:
--     • RS.dest_tag          (so the EU knows where to write)
--     • ARF[arch_dest].tag   (architectural → physical mapping)
--     • ROB.renamed_reg      (for wakeup and future flush reference)
--   The OLD tag that was in ARF[arch_dest].tag before this dispatch is saved
--   into ROB.old_dest_tag — it will be freed at commit.
--
-- COMMIT (push, up to 2 per cycle):
--   When the ROB head commits: push ROB.old_dest_tag back to the tail.
--   This frees the physical register that was in use BEFORE this instruction
--   renamed the destination — it is no longer needed for recovery.
--
-- MISPREDICTION FLUSH (push-back, up to 2 per cycle, multi-cycle):
--   Walk the ROB from tail toward the branch entry.  For each speculative
--   entry push its renamed_reg back.  The mispredict_recovery.vhd drives
--   flush_tag0/1 each cycle until done.
--
-- STALL:
--   If fewer free tags remain than the number of writes in the fetch bundle,
--   assert stall so the front end does not dispatch.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rrf_freelist is
    generic (
        RRF_DEPTH    : integer := 32;   -- physical register count
        TAG_BITS     : integer := 5     -- log2(RRF_DEPTH)
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;

        -- -----------------------------------------------------------------
        -- DISPATCH: pop up to 2 tags per cycle
        -- -----------------------------------------------------------------
        pop0_en       : in  std_logic;   -- instruction 0 needs a tag
        pop0_tag      : out std_logic_vector(TAG_BITS-1 downto 0);  -- allocated tag

        pop1_en       : in  std_logic;   -- instruction 1 needs a tag
        pop1_tag      : out std_logic_vector(TAG_BITS-1 downto 0);

        -- -----------------------------------------------------------------
        -- COMMIT: push up to 2 old tags per cycle
        -- -----------------------------------------------------------------
        push0_en      : in  std_logic;
        push0_tag     : in  std_logic_vector(TAG_BITS-1 downto 0);

        push1_en      : in  std_logic;
        push1_tag     : in  std_logic_vector(TAG_BITS-1 downto 0);

        -- -----------------------------------------------------------------
        -- FLUSH: push up to 2 speculative tags per cycle (from mispredict)
        -- -----------------------------------------------------------------
        flush0_en     : in  std_logic;
        flush0_tag    : in  std_logic_vector(TAG_BITS-1 downto 0);

        flush1_en     : in  std_logic;
        flush1_tag    : in  std_logic_vector(TAG_BITS-1 downto 0);

        -- -----------------------------------------------------------------
        -- Status
        -- -----------------------------------------------------------------
        free_count    : out std_logic_vector(TAG_BITS downto 0);
        -- Stall if we cannot satisfy the requested pops this cycle
        stall         : out std_logic
    );
end entity rrf_freelist;

architecture rtl of rrf_freelist is

    -- FIFO storage
    type fifo_t is array (0 to RRF_DEPTH-1) of
                   std_logic_vector(TAG_BITS-1 downto 0);
    signal fifo    : fifo_t;

    signal head    : unsigned(TAG_BITS-1 downto 0) := (others => '0');
    signal tail    : unsigned(TAG_BITS-1 downto 0) := (others => '0');
    signal count   : unsigned(TAG_BITS   downto 0) := (others => '0');

    -- Lookahead for combinational pop_tag outputs
    signal tag0_out : std_logic_vector(TAG_BITS-1 downto 0);
    signal tag1_out : std_logic_vector(TAG_BITS-1 downto 0);

    -- How many pops are requested this cycle
    signal pops_needed : unsigned(1 downto 0);

begin

    -- ------------------------------------------------------------------
    -- Combinational: expose the next two free tags without consuming them
    -- ------------------------------------------------------------------
    tag0_out <= fifo(to_integer(head));
    tag1_out <= fifo(to_integer(head + 1));

    pop0_tag <= tag0_out;
    pop1_tag <= tag1_out when pop0_en = '1' else tag0_out;
    -- (if only pop1 fires without pop0, it still gets head; the clocked
    --  process advances head correctly)

    pops_needed <= ("0" & pop0_en) + ("0" & pop1_en);

    stall <= '1' when count < pops_needed else '0';

    free_count <= std_logic_vector(count);

    -- ------------------------------------------------------------------
    -- Clocked: advance head/tail, update count
    -- ------------------------------------------------------------------
    process(clk, rst)
        variable new_head  : unsigned(TAG_BITS-1 downto 0);
        variable new_tail  : unsigned(TAG_BITS-1 downto 0);
        variable pop_cnt   : unsigned(1 downto 0) := (others => '0');
        variable push_cnt  : unsigned(2 downto 0) := (others => '0');
    begin
        if rst = '1' then
            -- Populate free list with all RRF indices
            for i in 0 to RRF_DEPTH-1 loop
                fifo(i) <= std_logic_vector(to_unsigned(i, TAG_BITS));
            end loop;
            head  <= (others => '0');
            tail  <= to_unsigned(RRF_DEPTH, TAG_BITS);
            count <= to_unsigned(RRF_DEPTH, TAG_BITS+1);

        elsif rising_edge(clk) then
            new_head := head;
            new_tail := tail;
            pop_cnt  := (others => '0');
            push_cnt := (others => '0');

            -- ---- POPS (dispatch) ----
            -- Only pop if we actually have enough entries (stall suppresses
            -- dispatch, so in steady state count >= pops_needed here)
            if pop0_en = '1' and count > push_cnt then
                new_head := new_head + 1;
                pop_cnt  := pop_cnt + 1;
            end if;
            if pop1_en = '1' and count > pop_cnt then
                new_head := new_head + 1;
                pop_cnt  := pop_cnt + 1;
            end if;

            -- ---- COMMIT PUSHES ----
            if push0_en = '1' then
                fifo(to_integer(new_tail)) <= push0_tag;
                new_tail  := new_tail + 1;
                push_cnt  := push_cnt + 1;
            end if;
            if push1_en = '1' then
                fifo(to_integer(new_tail)) <= push1_tag;
                new_tail  := new_tail + 1;
                push_cnt  := push_cnt + 1;
            end if;

            -- ---- FLUSH PUSHES ----
            if flush0_en = '1' then
                fifo(to_integer(new_tail)) <= flush0_tag;
                new_tail  := new_tail + 1;
                push_cnt  := push_cnt + 1;
            end if;
            if flush1_en = '1' then
                fifo(to_integer(new_tail)) <= flush1_tag;
                new_tail  := new_tail + 1;
                push_cnt  := push_cnt + 1;
            end if;

            head  <= new_head;
            tail  <= new_tail;
            count <= count - pop_cnt + push_cnt;
        end if;
    end process;

end architecture rtl;
