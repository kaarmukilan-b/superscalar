-- =============================================================================
-- File       : branch_predictor.vhd
-- Project    : IITB-RISC 2-way Superscalar Branch Predictor
-- Module     : Top-Level Branch Predictor
-- Pipeline   : IF -> ID -> Schedule -> Dispatch -> Execute -> Commit -> Retire
-- -----------------------------------------------------------------------------
-- Description:
--   Top-level wrapper integrating:
--     - Two BTBs (one per fetch slot) with 2-bit saturating counters
--     - One Return Address Stack (RAS)
--     - Redirect and flush control logic
--
--   TWO-WAY FETCH BUNDLE RULES:
--     Slot 0 = instruction at fetch_pc
--     Slot 1 = instruction at fetch_pc + 2
--
--     Case A: Slot 0 predicts TAKEN
--       -> redirect fetch to s0 target
--       -> squash_slot1 = '1' (slot 1 is on wrong path)
--
--     Case B: Slot 0 NOT taken, Slot 1 predicts TAKEN
--       -> redirect fetch to s1 target
--       -> squash_slot1 = '0' (slot 0 is valid)
--
--     Case C: Neither slot predicts taken
--       -> next fetch PC = fetch_pc + 4 (normal sequential)
--
--   BRANCH RESOLUTION POLICY:
--     Unconditionals (JAL, JRI)    -> resolve at ID  : 1-cycle penalty
--     JLR (return)                 -> RAS at   ID  : 1-cycle penalty
--     Conditionals (BEQ, BLT, BLE) -> resolve at EX : 4-cycle penalty
--
--   On misprediction (from Execute), flush_en is asserted and all
--   in-flight instructions younger than the branch are squashed.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity branch_predictor is
    generic (
        ADDR_WIDTH   : integer := 16;
        BTB_ENTRIES  : integer := 16;
        BTB_IDX_BITS : integer := 4;
        BTB_TAG_BITS : integer := 11;
        RAS_DEPTH    : integer := 4
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        -- =================================================================
        -- IF Stage: Prediction Inputs / Outputs
        -- =================================================================

        -- Current fetch PC (slot 0). Slot 1 is fetch_pc + 2 internally.
        fetch_pc       : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Per-slot prediction results (for debug / pipeline registers)
        s0_pred_taken  : out std_logic;
        s0_pred_target : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        s1_pred_taken  : out std_logic;
        s1_pred_target : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Redirect: override the sequential PC+4 fetch
        redirect_en    : out std_logic;
        redirect_pc    : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- When slot 0 predicts taken, slot 1 must be invalidated
        squash_slot1   : out std_logic;

        -- =================================================================
        -- ID Stage: Call / Return Detection (drives RAS)
        -- =================================================================

        -- Assert when a JAL or JLR-acting-as-call is decoded.
        -- id_call_retaddr = PC+2 of that instruction (return address to save).
        id_is_call      : in std_logic;
        id_call_retaddr : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Assert when a JLR acting as a return is decoded.
        -- The RAS top is used as the predicted target (already output on
        -- s0_pred_target / s1_pred_target via BTB, but RAS overrides for JLR).
        id_is_return    : in std_logic;

        -- Override: when a JLR return is in ID, provide RAS target to IF
        -- so the fetch can be redirected immediately (1-cycle penalty).
        ras_pred_valid  : out std_logic;
        ras_pred_target : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- =================================================================
        -- Execute Stage: Branch Resolution and BTB Update
        -- =================================================================

        -- Assert for one cycle when a branch instruction resolves in EX.
        ex_update_en     : in std_logic;
        -- PC of the resolved branch instruction
        ex_branch_pc     : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        -- Actual outcome (1 = taken, 0 = not taken)
        ex_branch_taken  : in std_logic;
        -- Actual target address (valid only when ex_branch_taken = '1')
        ex_branch_target : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- Assert when the prediction was wrong (outcome OR target mismatch).
        ex_mispredicted  : in std_logic;
        -- The correct PC that the pipeline should have gone to.
        ex_correct_pc    : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- =================================================================
        -- Flush Control (to IF stage and pipeline)
        -- =================================================================

        -- Assert for one cycle when a misprediction is detected.
        -- All instructions younger than ex_branch_pc must be squashed.
        flush_en     : out std_logic;
        flush_target : out std_logic_vector(ADDR_WIDTH-1 downto 0)
    );
end entity branch_predictor;

architecture rtl of branch_predictor is

    -- =========================================================================
    -- Component: BTB
    -- =========================================================================
    component btb is
        generic (
            NUM_ENTRIES : integer;
            INDEX_BITS  : integer;
            TAG_BITS    : integer;
            ADDR_WIDTH  : integer
        );
        port (
            clk           : in  std_logic;
            rst           : in  std_logic;
            lookup_pc     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
            hit           : out std_logic;
            pred_taken    : out std_logic;
            pred_target   : out std_logic_vector(ADDR_WIDTH-1 downto 0);
            update_en     : in  std_logic;
            update_pc     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
            update_taken  : in  std_logic;
            update_target : in  std_logic_vector(ADDR_WIDTH-1 downto 0)
        );
    end component;

    -- =========================================================================
    -- Component: RAS
    -- =========================================================================
    component ras is
        generic (
            DEPTH      : integer;
            ADDR_WIDTH : integer
        );
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            push_en   : in  std_logic;
            push_addr : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
            pop_en    : in  std_logic;
            top_addr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
            empty     : out std_logic
        );
    end component;

    -- =========================================================================
    -- Internal Signals
    -- =========================================================================

    -- Slot 1 PC (always fetch_pc + 2)
    signal s1_pc : std_logic_vector(ADDR_WIDTH-1 downto 0);

    -- BTB slot 0 outputs
    signal s0_hit    : std_logic;
    signal s0_taken  : std_logic;
    signal s0_target : std_logic_vector(ADDR_WIDTH-1 downto 0);

    -- BTB slot 1 outputs
    signal s1_hit    : std_logic;
    signal s1_taken  : std_logic;
    signal s1_target : std_logic_vector(ADDR_WIDTH-1 downto 0);

    -- RAS outputs
    signal ras_top   : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal ras_empty : std_logic;

begin

    -- =========================================================================
    -- Slot 1 PC
    -- =========================================================================
    s1_pc <= std_logic_vector(unsigned(fetch_pc) + 2);

    -- =========================================================================
    -- BTB for Slot 0 (indexed by fetch_pc)
    -- =========================================================================
    u_btb_s0 : btb
        generic map (
            NUM_ENTRIES => BTB_ENTRIES,
            INDEX_BITS  => BTB_IDX_BITS,
            TAG_BITS    => BTB_TAG_BITS,
            ADDR_WIDTH  => ADDR_WIDTH
        )
        port map (
            clk           => clk,
            rst           => rst,
            lookup_pc     => fetch_pc,
            hit           => s0_hit,
            pred_taken    => s0_taken,
            pred_target   => s0_target,
            update_en     => ex_update_en,
            update_pc     => ex_branch_pc,
            update_taken  => ex_branch_taken,
            update_target => ex_branch_target
        );

    -- =========================================================================
    -- BTB for Slot 1 (indexed by fetch_pc + 2)
    -- =========================================================================
    u_btb_s1 : btb
        generic map (
            NUM_ENTRIES => BTB_ENTRIES,
            INDEX_BITS  => BTB_IDX_BITS,
            TAG_BITS    => BTB_TAG_BITS,
            ADDR_WIDTH  => ADDR_WIDTH
        )
        port map (
            clk           => clk,
            rst           => rst,
            lookup_pc     => s1_pc,
            hit           => s1_hit,
            pred_taken    => s1_taken,
            pred_target   => s1_target,
            update_en     => ex_update_en,
            update_pc     => ex_branch_pc,
            update_taken  => ex_branch_taken,
            update_target => ex_branch_target
        );

    -- =========================================================================
    -- Return Address Stack
    -- Pushed/popped from ID stage (1-cycle return penalty)
    -- =========================================================================
    u_ras : ras
        generic map (
            DEPTH      => RAS_DEPTH,
            ADDR_WIDTH => ADDR_WIDTH
        )
        port map (
            clk       => clk,
            rst       => rst,
            push_en   => id_is_call,
            push_addr => id_call_retaddr,
            pop_en    => id_is_return,
            top_addr  => ras_top,
            empty     => ras_empty
        );

    -- =========================================================================
    -- RAS Prediction Output
    -- When a JLR return is detected in ID, provide the popped address
    -- so IF can redirect immediately.
    -- =========================================================================
    ras_pred_valid  <= id_is_return and (not ras_empty);
    ras_pred_target <= ras_top;

    -- =========================================================================
    -- Per-slot Prediction Output (for pipeline registers in IF/ID)
    -- =========================================================================
    s0_pred_taken  <= s0_taken and s0_hit;
    s0_pred_target <= s0_target;
    s1_pred_taken  <= s1_taken and s1_hit;
    s1_pred_target <= s1_target;

    -- =========================================================================
    -- Redirect Logic  (combinational, consumed by IF stage)
    --
    -- Priority (highest to lowest):
    --   1. Misprediction flush from Execute  (overrides everything)
    --   2. RAS redirect from ID (JLR return, 1-cycle penalty)
    --   3. Slot 0 BTB predicts taken         (squash slot 1)
    --   4. Slot 1 BTB predicts taken         (slot 0 still valid)
    --   5. No redirect, next fetch = PC+4
    -- =========================================================================
    process(ex_mispredicted, ex_correct_pc,
            id_is_return, ras_empty, ras_top,
            s0_hit, s0_taken, s0_target,
            s1_hit, s1_taken, s1_target)
    begin
        -- Defaults: no action
        redirect_en  <= '0';
        redirect_pc  <= (others => '0');
        squash_slot1 <= '0';
        flush_en     <= '0';
        flush_target <= (others => '0');

        -- ------------------------------------------------------------------
        -- Priority 1: Misprediction flush (from Execute stage)
        -- Squashes all in-flight instructions younger than the branch.
        -- ------------------------------------------------------------------
        if ex_mispredicted = '1' then
            flush_en     <= '1';
            flush_target <= ex_correct_pc;

        -- ------------------------------------------------------------------
        -- Priority 2: JLR Return via RAS (from ID stage)
        -- 1-cycle penalty: only squash what is currently in IF.
        -- ------------------------------------------------------------------
        elsif id_is_return = '1' and ras_empty = '0' then
            redirect_en  <= '1';
            redirect_pc  <= ras_top;
            squash_slot1 <= '1';   -- anything already in IF is wrong path

        -- ------------------------------------------------------------------
        -- Priority 3: Slot 0 BTB hit, predict taken
        -- Slot 1 is on the wrong path and must be squashed.
        -- ------------------------------------------------------------------
        elsif s0_hit = '1' and s0_taken = '1' then
            redirect_en  <= '1';
            redirect_pc  <= s0_target;
            squash_slot1 <= '1';

        -- ------------------------------------------------------------------
        -- Priority 4: Slot 0 not taken, Slot 1 BTB hit, predict taken
        -- Slot 0 is valid. Redirect after this bundle.
        -- ------------------------------------------------------------------
        elsif s1_hit = '1' and s1_taken = '1' then
            redirect_en  <= '1';
            redirect_pc  <= s1_target;
            squash_slot1 <= '0';

        -- ------------------------------------------------------------------
        -- Priority 5: No prediction, sequential fetch (handled by IF stage)
        -- ------------------------------------------------------------------
        end if;

    end process;

end architecture rtl;
