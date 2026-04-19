library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rob_pkg.all;

entity mispredict_recovery is
    port (
        clk : in std_logic;
        rst : in std_logic;

           commit_valid_s0 : in std_logic;
        commit_entry_s0 : in rob_entry_t;

        commit_valid_s1 : in std_logic;
        commit_entry_s1 : in rob_entry_t;

        arf_committed    : in std_logic_vector(8*DATA_BITS-1 downto 0);

        rob_flush        : out std_logic;
        rs_flush         : out std_logic;

        arf_restore_en   : out std_logic;
        arf_restore_data : out std_logic_vector(8*DATA_BITS-1 downto 0);

        commit_mispredict : out std_logic;
        commit_correct_pc : out std_logic_vector(DATA_BITS-1 downto 0);

        commit_upd0_en     : out std_logic;
        commit_upd0_pc     : out std_logic_vector(DATA_BITS-1 downto 0);
        commit_upd0_taken  : out std_logic;
        commit_upd0_target : out std_logic_vector(DATA_BITS-1 downto 0);

        commit_upd1_en     : out std_logic;
        commit_upd1_pc     : out std_logic_vector(DATA_BITS-1 downto 0);
        commit_upd1_taken  : out std_logic;
        commit_upd1_target : out std_logic_vector(DATA_BITS-1 downto 0)
    );
end entity;

architecture rtl of mispredict_recovery is

    -- -----------------------------------------------------------------------
    -- Mispredict detection.
    -- Returns '1' if any of the three wrong cases apply.
    -- -----------------------------------------------------------------------
    function is_mispredicted(e : rob_entry_t) return std_logic is
    begin
        -- Case (a) and (b): direction wrong
        if e.bp_predicted /= e.actual_taken then
            return '1';
        end if;
        -- Case (c): direction right (both taken) but target wrong
        if e.actual_taken = '1' and e.bp_target /= e.actual_target then
            return '1';
        end if;
        return '0';
    end function;

    -- -----------------------------------------------------------------------
    -- Correct PC after a mispredict.
    -- -----------------------------------------------------------------------
    function get_correct_pc(e : rob_entry_t) return std_logic_vector is
    begin
        if e.actual_taken = '1' then
            -- Branch/jump was taken — go to the resolved target
            return e.actual_target;
        else
            -- Branch was not taken — resume sequential fetch.
            -- ip+4 because this is 2-wide fetch: ip was slot 0,
            -- ip+2 was slot 1 (already wrong-path), ip+4 is next pair.
            return std_logic_vector(unsigned(e.ip) + 4);
        end if;
    end function;

    -- Internal mispredict flags (combinational)
    signal mis0 : std_logic;
    signal mis1 : std_logic;

begin

    -- -----------------------------------------------------------------------
    -- Evaluate mispredict per slot.
    -- Only fires if the slot is valid and the instruction is a branch/jump.
    -- -----------------------------------------------------------------------
    mis0 <= is_mispredicted(commit_entry_s0)
                when (commit_valid_s0 = '1' and
                      commit_entry_s0.is_branch = '1')
                else '0';

    mis1 <= is_mispredicted(commit_entry_s1)
                when (commit_valid_s1 = '1' and
                      commit_entry_s1.is_branch = '1')
                else '0';

    -- -----------------------------------------------------------------------
    -- BTB training — fires for every branch/jump that commits, correct or
    -- not. Correct predictions reinforce the saturating counter toward the
    -- right direction; wrong predictions correct it. The BTB itself handles
    -- the not-taken entry creation policy (see btb.vhd).
    -- -----------------------------------------------------------------------
    commit_upd0_en     <= '1' when (commit_valid_s0 = '1' and
                                    commit_entry_s0.is_branch = '1')
                          else '0';
    commit_upd0_pc     <= commit_entry_s0.ip;
    commit_upd0_taken  <= commit_entry_s0.actual_taken;
    commit_upd0_target <= commit_entry_s0.actual_target;

    commit_upd1_en     <= '1' when (commit_valid_s1 = '1' and
                                    commit_entry_s1.is_branch = '1')
                          else '0';
    commit_upd1_pc     <= commit_entry_s1.ip;
    commit_upd1_taken  <= commit_entry_s1.actual_taken;
    commit_upd1_target <= commit_entry_s1.actual_target;

    -- -----------------------------------------------------------------------
    -- Flush and redirect.
    --
    -- Priority: slot 0 over slot 1.
    --   Slot 0 is older. If it mispredicted, the correct path diverges at
    --   slot 0's PC — slot 1's mispredict is irrelevant because slot 1 will
    --   be re-fetched from scratch after the flush anyway.
    --   Slot 1's BTB training still fires regardless (it is just a counter
    --   update — harmless and informative).
    -- -----------------------------------------------------------------------
    process(mis0, mis1, commit_entry_s0, commit_entry_s1, arf_committed)
    begin
        -- Safe defaults: no flush, no redirect
        rob_flush         <= '0';
        rs_flush          <= '0';
        arf_restore_en    <= '0';
        arf_restore_data  <= arf_committed;
        commit_mispredict <= '0';
        commit_correct_pc <= (others => '0');

        if mis0 = '1' then
            -- Slot 0 mispredicted.
            -- Flush the whole pipeline and redirect to slot 0's correct PC.
            rob_flush         <= '1';
            rs_flush          <= '1';
            arf_restore_en    <= '1';
            arf_restore_data  <= arf_committed;
            commit_mispredict <= '1';
            commit_correct_pc <= get_correct_pc(commit_entry_s0);

        elsif mis1 = '1' then
            -- Slot 1 mispredicted (slot 0 was fine).
            -- Still need a full flush — wrong-path instructions behind
            -- slot 1 are already in the ROB and RS.
            rob_flush         <= '1';
            rs_flush          <= '1';
            arf_restore_en    <= '1';
            arf_restore_data  <= arf_committed;
            commit_mispredict <= '1';
            commit_correct_pc <= get_correct_pc(commit_entry_s1);
        end if;

    end process;

end architecture rtl;
