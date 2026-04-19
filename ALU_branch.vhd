library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ALU_branch is
    port (
        -- Inputs
		  ALU_valid			 : in std_logic;
        opcode           : in  std_logic_vector(3 downto 0);
        pc_in            : in  std_logic_vector(15 downto 0);
        operand_1        : in  std_logic_vector(15 downto 0); -- Usually RA
        operand_2        : in  std_logic_vector(15 downto 0); -- Usually RB
        imm_9            : in  std_logic_vector(8 downto 0);
        
        -- Tag/Valid Inputs (Wire passing)
        dest_tag_reg_in  : in  std_logic_vector(2 downto 0);
        
        -- Outputs
        take_branch      : out std_logic; -- 1 if Jump or Branch Condition met
        target_address   : out std_logic_vector(15 downto 0);
        
        -- Register Writeback (for Link operations)
        dest_tag_reg_out : out std_logic_vector(2 downto 0);
        dest_reg_valid   : out std_logic;
        dest_reg_value   : out std_logic_vector(15 downto 0)
    );
end entity;

architecture struct of ALU_branch is

    -- Internal Signals for Immediate Handling
    signal imm6_extended : std_logic_vector(15 downto 0);
    signal imm9_extended : std_logic_vector(15 downto 0);
    
    -- Comparison Signals
    signal is_equal      : std_logic;
    signal is_less       : std_logic;
    
    -- Address Calculation Signals
    signal pc_plus_2     : unsigned(15 downto 0);
    signal pc_plus_imm6  : unsigned(15 downto 0);
    signal pc_plus_imm9  : unsigned(15 downto 0);
    signal ra_plus_imm9  : unsigned(15 downto 0);

begin

    -- 1. Immediate Formatting [cite: 28, 30]
    -- BEQ, BLT, BLE use 6-bit signed immediate 
    imm6_extended <= std_logic_vector(resize(signed(imm_9(5 downto 0)), 16));
    -- JAL, JRI use 9-bit signed immediate [cite: 30, 32]
    imm9_extended <= std_logic_vector(resize(signed(imm_9), 16));

    -- 2. Comparison Logic
    is_equal <= '1' when (operand_1 = operand_2) else '0';
    is_less  <= '1' when (signed(operand_1) < signed(operand_2)) else '0';

    -- 3. Address Calculations 
    pc_plus_2    <= unsigned(pc_in) + 2;
    -- Targets use Imm*2 for PC-relative branches 
    pc_plus_imm6 <= unsigned(pc_in) + unsigned(imm6_extended(14 downto 0) & '0');
    pc_plus_imm9 <= unsigned(pc_in) + unsigned(imm9_extended(14 downto 0) & '0');
    -- JRI uses RA + Imm*2 
    ra_plus_imm9 <= unsigned(operand_1) + unsigned(imm9_extended(14 downto 0) & '0');

    -- 4. Branch Decision & Address Multiplexing
    process(opcode, is_equal, is_less, pc_plus_2, pc_plus_imm6, pc_plus_imm9, ra_plus_imm9, operand_2)
    begin
        -- Defaults
        take_branch    <= '0';
        target_address <= std_logic_vector(pc_plus_2);
        dest_reg_valid <= '0';
        dest_reg_value <= (others => '0');

        case opcode is
            when "1000" => -- BEQ 
                if is_equal = '1' then
                    take_branch    <= '1';
                    target_address <= std_logic_vector(pc_plus_imm6);
                end if;

            when "1001" => -- BLT 
                if is_less = '1' then
                    take_branch    <= '1';
                    target_address <= std_logic_vector(pc_plus_imm6);
                end if;

            when "1010" => -- BLE (Corrected Opcode) [cite: 51, 72]
                if (is_less = '1' or is_equal = '1') then
                    take_branch    <= '1';
                    target_address <= std_logic_vector(pc_plus_imm6);
                end if;

            when "1100" => -- JAL 
                take_branch    <= '1';
                target_address <= std_logic_vector(pc_plus_imm9);
                -- Link: Store PC+2 in RA 
                dest_reg_valid <= '1';
                dest_reg_value <= std_logic_vector(pc_plus_2);

            when "1101" => -- JLR 
                take_branch    <= '1';
                target_address <= operand_2; -- Branch to RB 
                -- Link: Store PC+2 in RA 
                dest_reg_valid <= '1';
                dest_reg_value <= std_logic_vector(pc_plus_2);

            when "1111" => -- JRI 
                take_branch    <= '1';
                target_address <= std_logic_vector(ra_plus_imm9);

            when others =>
                null;
        end case;
    end process;

    -- Wire passing for destination tags
    dest_tag_reg_out <= dest_tag_reg_in & ALU_valid;

end architecture;