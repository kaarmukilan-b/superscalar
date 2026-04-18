-- =============================================================================
-- branch_predictor_train.vhd
-- Branch Predictor + BTB with Commit-Time Training for IITB-RISC Superscalar
--
-- ARCHITECTURE
-- ============
-- Prediction:   2-bit saturating counter per BTB entry (Strongly/Weakly
--               Not-Taken = 00/01, Weakly/Strongly Taken = 10/11).
-- BTB:          Direct-mapped, indexed by PC[BTB_IDX_BITS+1 : 2] (byte
--               addresses, instructions always 2-byte aligned).
--               Each entry stores: valid, tag (upper PC bits), target PC,
--               2-bit counter.
-- Training:     Triggered ONLY at ROB commit of a branch.
--               Reason: training at EX would include instructions from the
--               wrong path (after a misprediction not yet committed).
--               Training at commit guarantees we only learn from correct-path
--               branches.
--
-- COMMIT-TIME TRAINING LOGIC
-- ==========================
-- When ROB head commits a branch instruction:
--   1. Compare ROB.branch_predicted (stored at dispatch from predictor)
--      against actual_taken (computed by EX and stored in ROB.completed).
--   2. If they differ → misprediction:
--         a. Assert flush signal to mispredict_recovery.vhd.
--         b. Update BTB counter in the direction of actual_taken.
--         c. Write actual target PC into BTB entry.
--   3. If they match → correct prediction:
--         a. Still update the saturating counter (reinforce).
--         b. No flush needed.
--
-- PREDICT INTERFACE
-- =================
-- Every cycle the fetch unit supplies the current PC.  This unit returns
-- a prediction + predicted_target within the same cycle (combinational path
-- through the BTB SRAM).
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity branch_predictor_train is
    generic (
        BTB_ENTRIES    : integer := 64;   -- must be power-of-2
        BTB_IDX_BITS   : integer := 6;    -- log2(BTB_ENTRIES)
        ADDR_BITS      : integer := 16
    );
    port (
        clk               : in  std_logic;
        rst               : in  std_logic;

        -- -----------------------------------------------------------------
        -- PREDICT interface (combinational, used by Fetch stage)
        -- -----------------------------------------------------------------
        fetch_pc          : in  std_logic_vector(ADDR_BITS-1 downto 0);
        pred_taken        : out std_logic;   -- '1' = predict taken
        pred_target       : out std_logic_vector(ADDR_BITS-1 downto 0);
        pred_valid        : out std_logic;   -- '1' = BTB hit (tag matches)

        -- -----------------------------------------------------------------
        -- DISPATCH: latch the prediction made at fetch into the ROB entry
        -- (wired directly; ROB stores pred_taken as branch_predicted)
        -- This port is read-only for external logic — provided as a
        -- registered snapshot so dispatch sees a stable value.
        -- -----------------------------------------------------------------
        disp_pred_taken   : out std_logic;
        disp_pred_target  : out std_logic_vector(ADDR_BITS-1 downto 0);

        -- -----------------------------------------------------------------
        -- COMMIT-TIME TRAINING interface
        -- Driven by the ROB commit logic for branch instructions only.
        -- -----------------------------------------------------------------
        train_en          : in  std_logic;   -- '1' = committing a branch
        train_pc          : in  std_logic_vector(ADDR_BITS-1 downto 0);
        train_actual_taken: in  std_logic;   -- actual outcome from EX
        train_actual_tgt  : in  std_logic_vector(ADDR_BITS-1 downto 0);
        train_predicted   : in  std_logic;   -- what BP predicted at fetch

        -- -----------------------------------------------------------------
        -- MISPREDICTION outputs → drive mispredict_recovery.vhd
        -- -----------------------------------------------------------------
        mispredict        : out std_logic;   -- mismatch detected at commit
        correct_pc        : out std_logic_vector(ADDR_BITS-1 downto 0)
    );
end entity branch_predictor_train;

architecture rtl of branch_predictor_train is

    -- ------------------------------------------------------------------
    -- BTB entry
    -- ------------------------------------------------------------------
    type btb_entry_t is record
        valid   : std_logic;
        tag     : std_logic_vector(ADDR_BITS-BTB_IDX_BITS-2 downto 0);
        target  : std_logic_vector(ADDR_BITS-1 downto 0);
        counter : std_logic_vector(1 downto 0);   -- 2-bit sat counter
    end record;

    type btb_t is array (0 to BTB_ENTRIES-1) of btb_entry_t;
    signal btb : btb_t;

    -- ------------------------------------------------------------------
    -- Index and tag extraction (PC is byte-addressed, word-aligned → bit 0
    -- is always 0; use bits [IDX+1 : 1] for index, rest as tag)
    -- ------------------------------------------------------------------
    -- fetch index
    signal f_idx : integer range 0 to BTB_ENTRIES-1;
    signal f_tag : std_logic_vector(ADDR_BITS-BTB_IDX_BITS-2 downto 0);
    -- train index
    signal t_idx : integer range 0 to BTB_ENTRIES-1;
    signal t_tag : std_logic_vector(ADDR_BITS-BTB_IDX_BITS-2 downto 0);

    -- Registered prediction for dispatch
    signal disp_taken_r  : std_logic := '0';
    signal disp_target_r : std_logic_vector(ADDR_BITS-1 downto 0) := (others => '0');

    -- ------------------------------------------------------------------
    -- Saturating counter update helper (pure function)
    -- ------------------------------------------------------------------
    function sat_update(ctr : std_logic_vector(1 downto 0);
                        taken : std_logic)
        return std_logic_vector is
    begin
        if taken = '1' then
            -- Increment toward 11
            case ctr is
                when "00"   => return "01";
                when "01"   => return "10";
                when "10"   => return "11";
                when others => return "11";
            end case;
        else
            -- Decrement toward 00
            case ctr is
                when "11"   => return "10";
                when "10"   => return "01";
                when "01"   => return "00";
                when others => return "00";
            end case;
        end if;
    end function;

begin

    -- ------------------------------------------------------------------
    -- Index / tag decode
    -- ------------------------------------------------------------------
    f_idx <= to_integer(unsigned(fetch_pc(BTB_IDX_BITS downto 1)));
    f_tag <= fetch_pc(ADDR_BITS-1 downto BTB_IDX_BITS+1);

    t_idx <= to_integer(unsigned(train_pc(BTB_IDX_BITS downto 1)));
    t_tag <= train_pc(ADDR_BITS-1 downto BTB_IDX_BITS+1);

    -- ------------------------------------------------------------------
    -- PREDICT (combinational)
    -- ------------------------------------------------------------------
    pred_valid  <= btb(f_idx).valid and
                   '1' when btb(f_idx).tag = f_tag else '0';
    pred_taken  <= btb(f_idx).counter(1) when
                   (btb(f_idx).valid = '1' and btb(f_idx).tag = f_tag)
                   else '0';
    pred_target <= btb(f_idx).target when
                   (btb(f_idx).valid = '1' and btb(f_idx).tag = f_tag)
                   else (others => '0');

    -- ------------------------------------------------------------------
    -- Registered snapshot for dispatch (1-cycle latency from fetch)
    -- ------------------------------------------------------------------
    disp_pred_taken  <= disp_taken_r;
    disp_pred_target <= disp_target_r;

    -- ------------------------------------------------------------------
    -- Misprediction detection (combinational from commit signals)
    -- A misprediction is: prediction ≠ actual outcome.
    -- ------------------------------------------------------------------
    mispredict <= train_en and (train_predicted xor train_actual_taken);
    correct_pc <= train_actual_tgt when train_actual_taken = '1'
                  else std_logic_vector(unsigned(train_pc) + 2);
    -- If the branch was NOT taken the correct next-PC is PC+2 (16-bit words)

    -- ------------------------------------------------------------------
    -- Clocked: BTB update + prediction latch
    -- ------------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            for i in 0 to BTB_ENTRIES-1 loop
                btb(i).valid   <= '0';
                btb(i).counter <= "01";   -- weakly not-taken
                btb(i).target  <= (others => '0');
                btb(i).tag     <= (others => '0');
            end loop;
            disp_taken_r  <= '0';
            disp_target_r <= (others => '0');

        elsif rising_edge(clk) then

            -- ---- Latch prediction for dispatch ----
            disp_taken_r  <= pred_taken;
            disp_target_r <= pred_target;

            -- ---- Commit-time BTB training ----
            if train_en = '1' then
                btb(t_idx).valid   <= '1';
                btb(t_idx).tag     <= t_tag;
                btb(t_idx).target  <= train_actual_tgt;
                btb(t_idx).counter <= sat_update(btb(t_idx).counter,
                                                 train_actual_taken);
                -- Note: we update the target unconditionally with the actual
                -- target so indirect branches (JLR, JRI) stay up to date.
            end if;

        end if;
    end process;

end architecture rtl;
