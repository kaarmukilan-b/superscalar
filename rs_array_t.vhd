library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- Package definition to hold the RS record type
package rs_types is
    type rs_entry_t is record
        busy           : std_logic;
        PC             : std_logic_vector(15 downto 0);
        opcode         : std_logic_vector(6 downto 0);
        opr1           : std_logic_vector(15 downto 0);
        opr1_valid     : std_logic;
        opr1_tag       : std_logic_vector(4 downto 0);
        opr2           : std_logic_vector(15 downto 0);
        opr2_valid     : std_logic;
        opr2_tag       : std_logic_vector(4 downto 0);
        imm9_opr       : std_logic_vector(8 downto 0);
        imm9_valid     : std_logic;
        dest_tag       : std_logic_vector(4 downto 0);
        ROB_index      : std_logic_vector(4 downto 0); -- Assuming 32-entry ROB
        carry_value    : std_logic;
        carry_tag      : std_logic_vector(4 downto 0);
        carry_valid    : std_logic;
        carry_dest_tag : std_logic_vector(4 downto 0);
        zero_value     : std_logic;
        zero_tag       : std_logic_vector(4 downto 0);
        zero_valid     : std_logic;
        zero_dest_tag  : std_logic_vector(4 downto 0);
        PCnext_pred    : std_logic_vector(15 downto 0);
        PC_next_valid  : std_logic;
        ready          : std_logic;
    end record;
    
    type rs_array_t is array (natural range <>) of rs_entry_t;
end package;

-------------------------------------------------------------------

