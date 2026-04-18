-- =============================================================================
-- mispredict_recovery.vhd
-- Branch Misprediction Recovery Unit for IITB-RISC Superscalar Processor
--
-- SEQUENCE OF EVENTS
-- ==================
-- Cycle N   : Branch EU detects that the predicted target ≠ actual target
--             and asserts branch_mispredict.
-- Cycle N   : This unit latches the faulting ROB entry index (branch_rob_idx).
-- Cycle N+1 : FLUSH phase:
--   (a) Walk ROB from (branch_rob_idx+1) to (rob_tail-1), i.e. all
--       speculatively-issued instructions younger than the branch.
--   (b) For each such entry: return its renamed destination tag to the
--       RRF free list; clear the RS entry if it hasn't issued yet.
--   (c) Restore the ARF from the committed state held in the ROB for
--       entries at or before the branch.
--   (d) Set PC to the correct branch target.
--   (e) Assert rob_flush, rs_flush to clear pipeline registers.
--
-- ROB entry layout (ROB_DEPTH = 64):
--   busy         : 1  bit
--   ip           : 16 bits  – PC of the instruction
--   r_dest       : 3  bits  – architectural destination register
--   renamed_reg  : 5  bits  – RRF tag assigned at dispatch (needed for free)
--   old_dest_tag : 5  bits  – RRF tag that was mapped to r_dest BEFORE dispatch
--                              (needed to restore ARF on flush)
--   spec         : 1  bit   – instruction is speculative
--   exe          : 1  bit   – execution has started
--   issue        : 1  bit   – issued to an EU
--   completed    : 1  bit   – EU finished; result on CDB
--   valid        : 1  bit   – result value is valid
--   s_addr       : 16 bits  – store address (stores only)
--   s_data       : 16 bits  – store data   (stores only)
--   bp_predicted : 1  bit   – branch predictor's prediction (taken/not-taken)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rob_pkg is
    constant ROB_DEPTH  : integer := 64;
    constant ROB_IDX    : integer := 6;   -- log2(64)
    constant TAG_BITS   : integer := 5;
    constant DATA_BITS  : integer := 16;
    constant ARCH_REGS  : integer := 3;   -- 3-bit architectural reg id

    type rob_entry_t is record
        busy         : std_logic;
        ip           : std_logic_vector(DATA_BITS-1 downto 0);
        r_dest       : std_logic_vector(ARCH_REGS-1 downto 0);
        renamed_reg  : std_logic_vector(TAG_BITS-1  downto 0);
        old_dest_tag : std_logic_vector(TAG_BITS-1  downto 0);
        spec         : std_logic;
        exe          : std_logic;
        issue        : std_logic;
        completed    : std_logic;
        valid_result : std_logic;
        s_addr       : std_logic_vector(DATA_BITS-1 downto 0);
        s_data       : std_logic_vector(DATA_BITS-1 downto 0);
        bp_predicted : std_logic;
    end record;

    type rob_array_t is array (0 to ROB_DEPTH-1) of rob_entry_t;
end package rob_pkg;

-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rob_pkg.all;

entity mispredict_recovery is
    port (
        clk               : in  std_logic;
        rst               : in  std_logic;

        -- -----------------------------------------------------------------
        -- Misprediction signal from the Branch EU
        -- -----------------------------------------------------------------
        branch_mispredict : in  std_logic;
        -- Index of the mispredicted branch in the ROB
        branch_rob_idx    : in  std_logic_vector(ROB_IDX-1 downto 0);
        -- Correct target PC computed by the EU
        correct_pc        : in  std_logic_vector(DATA_BITS-1 downto 0);

        -- -----------------------------------------------------------------
        -- ROB state (FIFO pointers)
        -- -----------------------------------------------------------------
        rob_head          : in  std_logic_vector(ROB_IDX-1 downto 0);
        rob_tail          : in  std_logic_vector(ROB_IDX-1 downto 0);
        rob_array         : in  rob_array_t;

        -- -----------------------------------------------------------------
        -- ARF (8 architectural registers R0-R7)
        -- We restore by replaying the old_dest_tag chain.
        -- For simplicity the ARF snapshot at the last commit is passed in.
        -- -----------------------------------------------------------------
        arf_committed     : in  std_logic_vector(8*DATA_BITS-1 downto 0);

        -- -----------------------------------------------------------------
        -- Control outputs
        -- -----------------------------------------------------------------
        -- PC redirect
        pc_redirect       : out std_logic;
        pc_new            : out std_logic_vector(DATA_BITS-1 downto 0);

        -- Flush entire ROB / RS (active-high, one-cycle pulse)
        rob_flush         : out std_logic;
        rs_flush          : out std_logic;

        -- RRF free-list push: during flush we push all speculative tags back.
        -- Up to 2 tags freed per cycle (superscalar width = 2).
        free_tag0_valid   : out std_logic;
        free_tag0         : out std_logic_vector(TAG_BITS-1 downto 0);
        free_tag1_valid   : out std_logic;
        free_tag1         : out std_logic_vector(TAG_BITS-1 downto 0);

        -- ARF restore: broadcast the committed ARF snapshot
        arf_restore_en    : out std_logic;
        arf_restore_data  : out std_logic_vector(8*DATA_BITS-1 downto 0);

        -- Branch predictor update (to train the predictor)
        bp_update_en      : out std_logic;
        bp_update_pc      : out std_logic_vector(DATA_BITS-1 downto 0);
        bp_actual_taken   : out std_logic;

        -- Flush in progress (held until ROB is fully drained)
        flush_active      : out std_logic
    );
end entity mispredict_recovery;

architecture rtl of mispredict_recovery is

    -- FSM states
    type flush_state_t is (IDLE, FLUSH_ROB, DONE);
    signal state      : flush_state_t := IDLE;

    -- Walk pointer (iterates from branch+1 to tail during FLUSH_ROB)
    signal walk_ptr   : unsigned(ROB_IDX-1 downto 0) := (others => '0');
    signal branch_idx : unsigned(ROB_IDX-1 downto 0) := (others => '0');
    signal tail_snap  : unsigned(ROB_IDX-1 downto 0) := (others => '0');

    -- Latch the branch's ROB entry at misprediction time
    signal branch_ip  : std_logic_vector(DATA_BITS-1 downto 0)
                        := (others => '0');

    -- Internal signals
    signal flush_done : std_logic := '0';

begin

    -- ------------------------------------------------------------------
    -- Main FSM
    -- ------------------------------------------------------------------
    FSM: process(clk, rst)
        variable entry      : rob_entry_t;
        variable next_ptr   : unsigned(ROB_IDX-1 downto 0);
    begin
        if rst = '1' then
            state           <= IDLE;
            pc_redirect     <= '0';
            rob_flush       <= '0';
            rs_flush        <= '0';
            arf_restore_en  <= '0';
            free_tag0_valid <= '0';
            free_tag1_valid <= '0';
            bp_update_en    <= '0';
            flush_active    <= '0';
            walk_ptr        <= (others => '0');

        elsif rising_edge(clk) then
            -- Default: de-assert one-cycle pulses
            pc_redirect     <= '0';
            rob_flush       <= '0';
            rs_flush        <= '0';
            arf_restore_en  <= '0';
            free_tag0_valid <= '0';
            free_tag1_valid <= '0';
            bp_update_en    <= '0';

            case state is

                -- ---------------------------------------------------------
                when IDLE =>
                    flush_active <= '0';
                    if branch_mispredict = '1' then
                        -- Latch context
                        branch_idx <= unsigned(branch_rob_idx);
                        tail_snap  <= unsigned(rob_tail);
                        branch_ip  <= rob_array(
                                        to_integer(unsigned(branch_rob_idx))
                                      ).ip;

                        -- Redirect PC immediately (this cycle)
                        pc_redirect <= '1';
                        pc_new      <= correct_pc;

                        -- Tell BP about the misprediction
                        bp_update_en    <= '1';
                        bp_update_pc    <= rob_array(
                                             to_integer(unsigned(branch_rob_idx))
                                           ).ip;
                        bp_actual_taken <= '1';  -- we know it was taken

                        -- Start flush from the entry AFTER the branch
                        walk_ptr <= unsigned(branch_rob_idx) + 1;
                        state    <= FLUSH_ROB;
                        flush_active <= '1';
                    end if;

                -- ---------------------------------------------------------
                -- Walk younger entries and free their RRF tags (2 per cycle)
                -- ---------------------------------------------------------
                when FLUSH_ROB =>
                    flush_active <= '1';
                    rob_flush    <= '1';
                    rs_flush     <= '1';

                    -- Check if we've reached the tail (nothing left to free)
                    if walk_ptr = tail_snap then
                        -- Restore ARF from the committed snapshot
                        arf_restore_en   <= '1';
                        arf_restore_data <= arf_committed;
                        state            <= DONE;
                    else
                        -- Free tag at walk_ptr
                        entry := rob_array(to_integer(walk_ptr));
                        free_tag0_valid <= entry.busy;
                        free_tag0       <= entry.renamed_reg;

                        next_ptr := walk_ptr + 1;

                        -- Free a second tag this cycle if available
                        if next_ptr /= tail_snap then
                            entry := rob_array(to_integer(next_ptr));
                            free_tag1_valid <= entry.busy;
                            free_tag1       <= entry.renamed_reg;
                            walk_ptr        <= walk_ptr + 2;
                        else
                            free_tag1_valid <= '0';
                            walk_ptr        <= walk_ptr + 1;
                        end if;
                    end if;

                -- ---------------------------------------------------------
                when DONE =>
                    flush_active    <= '0';
                    arf_restore_en  <= '0';
                    state           <= IDLE;

                when others =>
                    state <= IDLE;

            end case;
        end if;
    end process FSM;

    -- ------------------------------------------------------------------
    -- The ARF restore data is driven directly from the committed snapshot
    -- (registered externally; this entity just broadcasts it on the
    --  arf_restore_en pulse).
    -- ------------------------------------------------------------------
    arf_restore_data <= arf_committed;

end architecture rtl;
