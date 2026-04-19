library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package rob_pkg is

    constant ROB_DEPTH    : integer := 64;  -- number of entries in ROB 
    constant ROB_IDX      : integer := 6;   -- log2(64) -- Address inside ROB 
    constant TAG_BITS_RR  : integer := 5;   -- length of the address in Rename Register File (32 entries)
    constant DATA_BITS    : integer := 16;  -- Data is 16 bits 
    constant ARCH_REGS    : integer := 3;   -- 3-bit architectural register id as ARF has 8 entries

    type rob_entry_t is record
        busy               : std_logic;                                              -- entry has a live instruction => 1; entry is vacant or instruction can be replaced => 0
        ip                 : std_logic_vector(DATA_BITS-1 downto 0);                 -- PC of the instruction 
        r_dest             : std_logic_vector(ARCH_REGS-1 downto 0);                 -- destination address for the instruction in ARF 
        renamed_reg        : std_logic_vector(TAG_BITS_RR-1 downto 0);               -- corresponding address in RRF where value is updated after executed 
        old_dest_tag       : std_logic_vector(TAG_BITS_RR-1 downto 0);               -- previous dest tag that may be freed at commit
        old_dest_tag_valid : std_logic;                                              -- when we need to free => 1; o/w 0

        exe                : std_logic;	  -- updated to 1 if execution completed 
        issue              : std_logic;     -- updated to 1 if issue finished 
		  completed          : std_logic;     -- issue and execute done => ready for commit and hence set as 1
        
		  value1             : std_logic_vector(DATA_BITS-1 downto 0);
        carry              : std_logic;     -- the carry bit after execution of the instruction
        zero               : std_logic;     -- the zero bit after execution of the instruction

        bp_predicted       : std_logic;
        bp_target          : std_logic_vector(DATA_BITS-1 downto 0);
        is_branch          : std_logic;
        is_store           : std_logic;

        actual_taken       : std_logic;
        actual_target      : std_logic_vector(DATA_BITS-1 downto 0);
    end record;

    type rob_array_t is array (0 to ROB_DEPTH-1) of rob_entry_t;

    constant ROB_ENTRY_RESET : rob_entry_t := (
        busy               => '0',
        ip                 => (others => '0'),
        r_dest             => (others => '0'),
        renamed_reg        => (others => '0'),
        old_dest_tag       => (others => '0'),
        old_dest_tag_valid => '0',
        exe                => '0',
        issue              => '0',
        completed          => '0',
        value1             => (others => '0'),
        carry              => '0',
        zero               => '0',
        bp_predicted       => '0',
        bp_target          => (others => '0'),
        is_branch          => '0',
        is_store           => '0',
        actual_taken       => '0',
        actual_target      => (others => '0')
    );

end package rob_pkg;


