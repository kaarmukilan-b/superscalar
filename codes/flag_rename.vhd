-- =============================================================================
-- flag_rename.vhd
-- Flag Register Renaming for IITB-RISC Superscalar (C and Z flags)
--
-- WHY THIS IS NEEDED
-- ==================
-- Instructions like ADC, ADZ, ACC, ACZ, NDC, NDZ read the C or Z flag as an
-- implicit source operand. In an out-of-order pipeline, a predicated instruction
-- dispatched after an in-flight ALU (which will WRITE C/Z later) must wait for
-- that in-flight result — not read the stale committed flag value.
--
-- SOLUTION: treat C and Z exactly like architectural registers.
--   Flag ARF   : 2 entries  (index 0 = C, index 1 = Z)
--                Each entry holds { busy:1, value:1, tag:FLAG_TAG_BITS }
--   Flag PRF   : FLAG_PRF_DEPTH physical flag registers
--                Each entry holds { busy:1, value:1, valid:1 }
--   Free list  : circular FIFO of free FLAG_PRF_DEPTH tags
--
-- DISPATCH (one or two instructions per cycle):
--   • If the instruction writes C/Z (all ADD/NAND variants): pop a free
--     physical flag tag, write it into flag_ARF[C].tag / flag_ARF[Z].tag,
--     stash the OLD tag in the ROB as old_flag_tag (for commit free).
--   • If the instruction READS C or Z (ADC/ADZ/ACC/ACZ/NDC/NDZ/NCZ/NCC):
--     look up flag_ARF[flag].tag → supply to RS as opr_flag / valid_flag.
--     If flag_ARF[flag].busy is set the value is not yet ready; RS must wait.
--
-- WAKEUP:
--   When an EU writes a flag result on the CDB, flag_PRF[tag].value and
--   .valid are updated — same mechanism as the integer CDB wakeup.
--
-- COMMIT:
--   Push the OLD physical flag tag (saved in ROB) back to the free list.
--   The new tag (now in flag_ARF) becomes the committed value.
--
-- FLUSH (misprediction):
--   Push all speculative flag tags from the ROB back to the free list in
--   reverse ROB order (youngest first) — exactly as integer tags.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity flag_rename is
    generic (
        FLAG_PRF_DEPTH  : integer := 16;   -- physical flag register count
        FLAG_TAG_BITS   : integer := 4     -- log2(FLAG_PRF_DEPTH)
    );
    port (
        clk              : in  std_logic;
        rst              : in  std_logic;

        -- -----------------------------------------------------------------
        -- DISPATCH interface (up to 2 instructions per cycle, superscalar)
        -- -----------------------------------------------------------------
        -- Instruction 0
        disp0_valid      : in  std_logic;
        disp0_writes_c   : in  std_logic;   -- '1' if instr writes Carry flag
        disp0_writes_z   : in  std_logic;   -- '1' if instr writes Zero flag
        disp0_reads_c    : in  std_logic;   -- '1' if instr is conditioned on C
        disp0_reads_z    : in  std_logic;   -- '1' if instr is conditioned on Z

        -- Instruction 1
        disp1_valid      : in  std_logic;
        disp1_writes_c   : in  std_logic;
        disp1_writes_z   : in  std_logic;
        disp1_reads_c    : in  std_logic;
        disp1_reads_z    : in  std_logic;

        -- -----------------------------------------------------------------
        -- Dispatch OUTPUTS → go into RS flag operand slot + ROB
        -- -----------------------------------------------------------------
        -- Instruction 0 flag operand (for the RS 3rd-operand slot)
        disp0_flag_tag   : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        disp0_flag_val   : out std_logic;   -- value if already valid
        disp0_flag_rdy   : out std_logic;   -- '1' = value is stable now
        -- Destination physical flag tag allocated for instr 0
        disp0_dst_c_tag  : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        disp0_dst_z_tag  : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        -- Old tag (must be stored in ROB for free-on-commit)
        disp0_old_c_tag  : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        disp0_old_z_tag  : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);

        -- Instruction 1
        disp1_flag_tag   : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        disp1_flag_val   : out std_logic;
        disp1_flag_rdy   : out std_logic;
        disp1_dst_c_tag  : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        disp1_dst_z_tag  : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        disp1_old_c_tag  : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        disp1_old_z_tag  : out std_logic_vector(FLAG_TAG_BITS-1 downto 0);

        -- -----------------------------------------------------------------
        -- CDB wakeup for flag results
        -- EU broadcasts (tag, value:1-bit) when a flag is produced
        -- -----------------------------------------------------------------
        cdb_flag_valid   : in  std_logic;
        cdb_flag_tag     : in  std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        cdb_flag_c_value : in  std_logic;   -- computed Carry
        cdb_flag_z_value : in  std_logic;   -- computed Zero

        -- -----------------------------------------------------------------
        -- COMMIT interface
        -- At commit, the ROB hands back the old physical tag to be freed.
        -- -----------------------------------------------------------------
        commit0_valid    : in  std_logic;
        commit0_old_c    : in  std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        commit0_frees_c  : in  std_logic;
        commit0_old_z    : in  std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        commit0_frees_z  : in  std_logic;

        commit1_valid    : in  std_logic;
        commit1_old_c    : in  std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        commit1_frees_c  : in  std_logic;
        commit1_old_z    : in  std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        commit1_frees_z  : in  std_logic;

        -- -----------------------------------------------------------------
        -- FLUSH (misprediction): push arbitrary tags back to free list
        -- -----------------------------------------------------------------
        flush_valid      : in  std_logic;
        flush_tag_c      : in  std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        flush_tag_z      : in  std_logic_vector(FLAG_TAG_BITS-1 downto 0);
        flush_has_c      : in  std_logic;
        flush_has_z      : in  std_logic;

        -- -----------------------------------------------------------------
        -- Status
        -- -----------------------------------------------------------------
        free_count       : out std_logic_vector(FLAG_TAG_BITS downto 0);
        stall_no_free    : out std_logic
    );
end entity flag_rename;

architecture rtl of flag_rename is

    -- ------------------------------------------------------------------
    -- Physical Flag Register File
    -- ------------------------------------------------------------------
    type flag_prf_entry_t is record
        busy  : std_logic;
        value : std_logic;   -- 1-bit flag value
        valid : std_logic;   -- result has been written by EU
    end record;
    type flag_prf_t is array (0 to FLAG_PRF_DEPTH-1) of flag_prf_entry_t;
    signal flag_prf : flag_prf_t;

    -- ------------------------------------------------------------------
    -- Flag Architectural Register File (index 0=C, index 1=Z)
    -- ------------------------------------------------------------------
    type flag_arf_entry_t is record
        busy  : std_logic;   -- in-flight write pending
        value : std_logic;   -- committed value
        tag   : std_logic_vector(FLAG_TAG_BITS-1 downto 0);
    end record;
    type flag_arf_t is array (0 to 1) of flag_arf_entry_t;
    signal flag_arf : flag_arf_t;

    -- ------------------------------------------------------------------
    -- Free list FIFO
    -- ------------------------------------------------------------------
    type freelist_t is array (0 to FLAG_PRF_DEPTH-1) of
                       std_logic_vector(FLAG_TAG_BITS-1 downto 0);
    signal freelist  : freelist_t;
    signal fl_head   : unsigned(FLAG_TAG_BITS-1 downto 0) := (others => '0');
    signal fl_tail   : unsigned(FLAG_TAG_BITS-1 downto 0) := (others => '0');
    signal fl_count  : unsigned(FLAG_TAG_BITS   downto 0) := (others => '0');

    -- ------------------------------------------------------------------
    -- Helper: peek at free list head (without popping)
    -- ------------------------------------------------------------------
    signal free_tag_peek0 : std_logic_vector(FLAG_TAG_BITS-1 downto 0);
    signal free_tag_peek1 : std_logic_vector(FLAG_TAG_BITS-1 downto 0);

begin

    free_tag_peek0 <= freelist(to_integer(fl_head));
    free_tag_peek1 <= freelist(to_integer(fl_head + 1));

    free_count   <= std_logic_vector(fl_count);
    stall_no_free <= '1' when fl_count = 0 else '0';

    -- ------------------------------------------------------------------
    -- Dispatch: read flag operand tags and allocate destination tags
    -- (combinational — outputs registered by caller)
    -- ------------------------------------------------------------------

    -- Instruction 0 reads C flag
    disp0_flag_tag <= flag_arf(0).tag when disp0_reads_c = '1' else
                      flag_arf(1).tag;   -- reads Z
    disp0_flag_val <= flag_prf(to_integer(unsigned(flag_arf(0).tag))).value
                         when disp0_reads_c = '1' else
                      flag_prf(to_integer(unsigned(flag_arf(1).tag))).value;
    disp0_flag_rdy <= flag_prf(to_integer(unsigned(flag_arf(0).tag))).valid
                         when disp0_reads_c = '1' else
                      flag_prf(to_integer(unsigned(flag_arf(1).tag))).valid;

    -- Old tags (needed by ROB for commit-time free)
    disp0_old_c_tag <= flag_arf(0).tag;
    disp0_old_z_tag <= flag_arf(1).tag;
    -- New destination tags come from head of free list
    disp0_dst_c_tag <= free_tag_peek0 when disp0_writes_c = '1' else (others => '0');
    disp0_dst_z_tag <= free_tag_peek0 when (disp0_writes_c = '0' and disp0_writes_z = '1')
                       else free_tag_peek1 when (disp0_writes_c = '1' and disp0_writes_z = '1')
                       else (others => '0');

    -- Instruction 1 (same logic, but ARF may have been updated by instr 0
    --  within the same dispatch bundle — handled in the clocked process below)
    disp1_flag_tag <= flag_arf(0).tag when disp1_reads_c = '1' else
                      flag_arf(1).tag;
    disp1_flag_val <= flag_prf(to_integer(unsigned(flag_arf(0).tag))).value
                         when disp1_reads_c = '1' else
                      flag_prf(to_integer(unsigned(flag_arf(1).tag))).value;
    disp1_flag_rdy <= flag_prf(to_integer(unsigned(flag_arf(0).tag))).valid
                         when disp1_reads_c = '1' else
                      flag_prf(to_integer(unsigned(flag_arf(1).tag))).valid;

    disp1_old_c_tag <= flag_arf(0).tag;
    disp1_old_z_tag <= flag_arf(1).tag;
    disp1_dst_c_tag <= free_tag_peek1 when disp1_writes_c = '1' else (others => '0');
    disp1_dst_z_tag <= free_tag_peek1 when (disp1_writes_c = '0' and disp1_writes_z = '1')
                       else (others => '0');

    -- ------------------------------------------------------------------
    -- Clocked: free list management + ARF/PRF update
    -- ------------------------------------------------------------------
    process(clk, rst)
        variable pops  : integer range 0 to 4 := 0;
        variable pushes: integer range 0 to 4 := 0;
        variable new_head : unsigned(FLAG_TAG_BITS-1 downto 0);
        variable new_tail : unsigned(FLAG_TAG_BITS-1 downto 0);
    begin
        if rst = '1' then
            -- Initialise free list with all physical tags
            for i in 0 to FLAG_PRF_DEPTH-1 loop
                freelist(i) <= std_logic_vector(to_unsigned(i, FLAG_TAG_BITS));
                flag_prf(i) <= ('0', '0', '1');   -- all free and valid (value=0)
            end loop;
            fl_head  <= (others => '0');
            fl_tail  <= to_unsigned(FLAG_PRF_DEPTH, FLAG_TAG_BITS);
            fl_count <= to_unsigned(FLAG_PRF_DEPTH, FLAG_TAG_BITS+1);
            -- ARF: C=0, Z=0, tag=0
            flag_arf(0) <= ('0', '0', (others => '0'));
            flag_arf(1) <= ('0', '0', (others => '0'));

        elsif rising_edge(clk) then
            pops   := 0;
            pushes := 0;

            -- ---- CDB wakeup: write flag value into PRF ----
            if cdb_flag_valid = '1' then
                flag_prf(to_integer(unsigned(cdb_flag_tag))).value <= cdb_flag_c_value;
                flag_prf(to_integer(unsigned(cdb_flag_tag))).valid <= '1';
                -- Also update ARF.value if this tag is current
                if flag_arf(0).tag = cdb_flag_tag then
                    flag_arf(0).value <= cdb_flag_c_value;
                    flag_arf(0).busy  <= '0';
                end if;
                if flag_arf(1).tag = cdb_flag_tag then
                    flag_arf(1).value <= cdb_flag_z_value;
                    flag_arf(1).busy  <= '0';
                end if;
            end if;

            -- ---- DISPATCH: pop free tags, update ARF ----
            new_head := fl_head;
            if disp0_valid = '1' then
                if disp0_writes_c = '1' and fl_count > to_unsigned(pops, FLAG_TAG_BITS+1) then
                    flag_prf(to_integer(new_head)).busy  <= '1';
                    flag_prf(to_integer(new_head)).valid <= '0';
                    flag_arf(0).tag  <= std_logic_vector(new_head);
                    flag_arf(0).busy <= '1';
                    new_head := new_head + 1;
                    pops := pops + 1;
                end if;
                if disp0_writes_z = '1' and fl_count > to_unsigned(pops, FLAG_TAG_BITS+1) then
                    flag_prf(to_integer(new_head)).busy  <= '1';
                    flag_prf(to_integer(new_head)).valid <= '0';
                    flag_arf(1).tag  <= std_logic_vector(new_head);
                    flag_arf(1).busy <= '1';
                    new_head := new_head + 1;
                    pops := pops + 1;
                end if;
            end if;
            if disp1_valid = '1' then
                if disp1_writes_c = '1' and fl_count > to_unsigned(pops, FLAG_TAG_BITS+1) then
                    flag_prf(to_integer(new_head)).busy  <= '1';
                    flag_prf(to_integer(new_head)).valid <= '0';
                    flag_arf(0).tag  <= std_logic_vector(new_head);
                    flag_arf(0).busy <= '1';
                    new_head := new_head + 1;
                    pops := pops + 1;
                end if;
                if disp1_writes_z = '1' and fl_count > to_unsigned(pops, FLAG_TAG_BITS+1) then
                    flag_prf(to_integer(new_head)).busy  <= '1';
                    flag_prf(to_integer(new_head)).valid <= '0';
                    flag_arf(1).tag  <= std_logic_vector(new_head);
                    flag_arf(1).busy <= '1';
                    new_head := new_head + 1;
                    pops := pops + 1;
                end if;
            end if;
            fl_head <= new_head;

            -- ---- COMMIT: push old tags back ----
            new_tail := fl_tail;
            if commit0_valid = '1' then
                if commit0_frees_c = '1' then
                    freelist(to_integer(new_tail))      <= commit0_old_c;
                    flag_prf(to_integer(unsigned(commit0_old_c))).busy <= '0';
                    new_tail := new_tail + 1;
                    pushes := pushes + 1;
                end if;
                if commit0_frees_z = '1' then
                    freelist(to_integer(new_tail))      <= commit0_old_z;
                    flag_prf(to_integer(unsigned(commit0_old_z))).busy <= '0';
                    new_tail := new_tail + 1;
                    pushes := pushes + 1;
                end if;
            end if;
            if commit1_valid = '1' then
                if commit1_frees_c = '1' then
                    freelist(to_integer(new_tail))      <= commit1_old_c;
                    flag_prf(to_integer(unsigned(commit1_old_c))).busy <= '0';
                    new_tail := new_tail + 1;
                    pushes := pushes + 1;
                end if;
                if commit1_frees_z = '1' then
                    freelist(to_integer(new_tail))      <= commit1_old_z;
                    flag_prf(to_integer(unsigned(commit1_old_z))).busy <= '0';
                    new_tail := new_tail + 1;
                    pushes := pushes + 1;
                end if;
            end if;

            -- ---- FLUSH: push speculative tags back ----
            if flush_valid = '1' then
                if flush_has_c = '1' then
                    freelist(to_integer(new_tail))      <= flush_tag_c;
                    flag_prf(to_integer(unsigned(flush_tag_c))).busy  <= '0';
                    flag_prf(to_integer(unsigned(flush_tag_c))).valid <= '1';
                    new_tail := new_tail + 1;
                    pushes := pushes + 1;
                end if;
                if flush_has_z = '1' then
                    freelist(to_integer(new_tail))      <= flush_tag_z;
                    flag_prf(to_integer(unsigned(flush_tag_z))).busy  <= '0';
                    flag_prf(to_integer(unsigned(flush_tag_z))).valid <= '1';
                    new_tail := new_tail + 1;
                    pushes := pushes + 1;
                end if;
            end if;

            fl_tail  <= new_tail;
            fl_count <= fl_count - pops + pushes;

        end if;
    end process;

end architecture rtl;
