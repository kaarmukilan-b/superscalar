library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity branch_predictor is
    generic (
        ADDR_WIDTH   : integer := 16;
        BTB_ENTRIES  : integer := 16;
        BTB_IDX_BITS : integer := 4;
        BTB_TAG_BITS : integer := 11
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        fetch_pc : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        commit_mispredict : in std_logic;
        commit_correct_pc : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        commit_upd0_en     : in std_logic;
        commit_upd0_pc     : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        commit_upd0_taken  : in std_logic;
        commit_upd0_target : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        commit_upd1_en     : in std_logic;
        commit_upd1_pc     : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        commit_upd1_taken  : in std_logic;
        commit_upd1_target : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        next_pc  : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        valid_s0 : out std_logic;
        valid_s1 : out std_logic;

        flush    : out std_logic
    );
end entity;

architecture rtl of branch_predictor is

    component btb
        generic (
            NUM_ENTRIES : integer;
            INDEX_BITS  : integer;
            TAG_BITS    : integer;
            ADDR_WIDTH  : integer
        );
        port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            lookup_pc   : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
            hit         : out std_logic;
            pred_taken  : out std_logic;
            pred_target : out std_logic_vector(ADDR_WIDTH-1 downto 0);
            upd0_en     : in  std_logic;
            upd0_pc     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
            upd0_taken  : in  std_logic;
            upd0_target : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
            upd1_en     : in  std_logic;
            upd1_pc     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
            upd1_taken  : in  std_logic;
            upd1_target : in  std_logic_vector(ADDR_WIDTH-1 downto 0)
        );
    end component;

    -- ================================================================
    -- Internal signals
    -- ================================================================
    -- PC of the second fetch slot
    signal s1_pc : std_logic_vector(ADDR_WIDTH-1 downto 0);

    -- BTB lookup results for slot 0 (fetch_pc) and slot 1 (fetch_pc+2)
    signal s0_hit, s0_taken : std_logic;
    signal s1_hit, s1_taken : std_logic;
    signal s0_target        : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal s1_target        : std_logic_vector(ADDR_WIDTH-1 downto 0);

begin

    -- ================================================================
    -- Slot 1 PC
    -- ================================================================
    s1_pc <= std_logic_vector(unsigned(fetch_pc) + 2);

    -- ================================================================
    -- BTB instance for slot 0 — looks up fetch_pc
    -- ================================================================
    u_btb_s0 : btb
        generic map (BTB_ENTRIES, BTB_IDX_BITS, BTB_TAG_BITS, ADDR_WIDTH)
        port map (
            clk         => clk,
            rst         => rst,
            lookup_pc   => fetch_pc,
            hit         => s0_hit,
            pred_taken  => s0_taken,
            pred_target => s0_target,
            upd0_en     => commit_upd0_en,
            upd0_pc     => commit_upd0_pc,
            upd0_taken  => commit_upd0_taken,
            upd0_target => commit_upd0_target,
            upd1_en     => commit_upd1_en,
            upd1_pc     => commit_upd1_pc,
            upd1_taken  => commit_upd1_taken,
            upd1_target => commit_upd1_target
        );

    -- ================================================================
    -- BTB instance for slot 1 — looks up fetch_pc+2
    -- Identical update ports to u_btb_s0 — both mirrors must stay in
    -- sync so a branch PC gives the same prediction regardless of which
    -- fetch slot it lands in.
    -- ================================================================
    u_btb_s1 : btb
        generic map (BTB_ENTRIES, BTB_IDX_BITS, BTB_TAG_BITS, ADDR_WIDTH)
        port map (
            clk         => clk,
            rst         => rst,
            lookup_pc   => s1_pc,
            hit         => s1_hit,
            pred_taken  => s1_taken,
            pred_target => s1_target,
            upd0_en     => commit_upd0_en,
            upd0_pc     => commit_upd0_pc,
            upd0_taken  => commit_upd0_taken,
            upd0_target => commit_upd0_target,
            upd1_en     => commit_upd1_en,
            upd1_pc     => commit_upd1_pc,
            upd1_taken  => commit_upd1_taken,
            upd1_target => commit_upd1_target
        );

    -- ================================================================
    -- next_pc and valid selection
    -- ================================================================
    process(commit_mispredict, commit_correct_pc,
            s0_hit, s0_taken, s0_target,
            s1_hit, s1_taken, s1_target,
            fetch_pc)
    begin
        -- Default: sequential fetch, both slots valid, no flush
        next_pc  <= std_logic_vector(unsigned(fetch_pc) + 4);
        valid_s0 <= '1';
        valid_s1 <= '1';
        flush    <= '0';

        -- Priority 1: commit mispredict
        -- Overrides everything. The correct PC comes from the committing
        -- instruction's ROB entry (computed at EX, carried to commit).
        if commit_mispredict = '1' then
            next_pc  <= commit_correct_pc;
            valid_s0 <= '0';
            valid_s1 <= '0';
            flush    <= '1';

        -- Priority 2: slot 0 predicts taken
        -- Slot 1's instruction is immediately after a taken branch — it
        -- is on the wrong path and must be discarded (valid_s1='0').
        elsif s0_hit = '1' and s0_taken = '1' then
            next_pc  <= s0_target;
            valid_s0 <= '1';
            valid_s1 <= '0';

        -- Priority 3: slot 1 predicts taken
        -- Slot 0 had no taken branch, so it is valid. Slot 1 is a taken
        -- branch — it executes but the next fetch goes to its target.
        elsif s1_hit = '1' and s1_taken = '1' then
            next_pc  <= s1_target;
            valid_s0 <= '1';
            valid_s1 <= '1';

        end if;
        -- Default (no branch predicted): next_pc = fetch_pc+4, both valid.
    end process;

end architecture;
