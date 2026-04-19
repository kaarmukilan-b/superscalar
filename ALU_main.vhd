library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rs_types.all;

entity ALU_main is
    port (
        -- Inputs
		  ALU_valid			 : in  std_logic;                    
        opcode           : in  std_logic_vector(3 downto 0);
        cond_bits        : in  std_logic_vector(1 downto 0); 
        comp_bit         : in  std_logic;                    
        operand_1        : in  std_logic_vector(15 downto 0);
        operand_2        : in  std_logic_vector(15 downto 0);
        imm_9            : in  std_logic_vector(8 downto 0);
        c_flag_in        : in  std_logic;
        z_flag_in        : in  std_logic;
        
        -- Destination Tag Inputs (Wire passing)
        dest_tag_reg_in  : in  std_logic_vector(4 downto 0);
        dest_tag_z_in    : in  std_logic_vector(4 downto 0);
        dest_tag_c_in    : in  std_logic_vector(4 downto 0);
        
        -- Outputs
        result           : out std_logic_vector(15 downto 0);
        z_flag_out       : out std_logic;
        c_flag_out       : out std_logic;
        
        -- Tag/Valid Outputs
        dest_tag_reg_out : out std_logic_vector(4 downto 0);
        dest_tag_z_out   : out std_logic_vector(4 downto 0);
        dest_tag_c_out   : out std_logic_vector(4 downto 0);
        dest_reg_valid   : out std_logic;
        dest_z_valid     : out std_logic;
        dest_c_valid     : out std_logic
    );
end entity;

architecture struct of ALU_main is

    -- Intermediate logic signals
    signal imm_6_ext       : std_logic_vector(15 downto 0);
    signal operand_2_complemented: std_logic_vector(15 downto 0);
    signal condition_met   : std_logic;
    
    -- Arithmetic/Logic calculation signals
    signal add_result      : unsigned(16 downto 0);
    signal nand_result     : std_logic_vector(15 downto 0);
    signal lli_result         : std_logic_vector(15 downto 0);
    
    -- Final selection signals
    signal final_res_int   : std_logic_vector(15 downto 0);
    signal final_c_int     : std_logic;

begin

    -- 1. Pre-processing: Sign Extension and Complementing
    imm_6_ext <= std_logic_vector(resize(signed(imm_9(5 downto 0)), 16)); 
    operand_2_complemented <= not operand_2 when comp_bit = '1' else operand_2; 

    -- 2. Condition Checking logic 
    condition_met <= '1' when (cond_bits = "00") else
                     '1' when (cond_bits = "10" and c_flag_in = '1') else
                     '1' when (cond_bits = "01" and z_flag_in = '1') else
                     '1' when (cond_bits = "11") else
                     '0';

    -- 3. Parallel Execution Logic
    -- ADD / ADI / AWC
		-- 3. Parallel Execution Logic
    
    -- Decide what the second operand and carry bit should be based on opcode
		 add_result <= 
			  -- Case for AWC (Add with Carry)
			  (unsigned('0' & operand_1) + unsigned('0' & operand_2_complemented) + unsigned(std_logic_vector'("" & c_flag_in))) 
			  when (opcode = "0001" and cond_bits = "11") else 
			  
			  -- Case for ADI (Add Immediate)
			  (unsigned('0' & operand_1) + unsigned('0' & imm_6_ext)) 
			  when (opcode = "0000") else 
			  
			  -- Default Case (ADA/ACA/ADC/ADZ)
			  (unsigned('0' & operand_1) + unsigned('0' & operand_2_complemented));
    -- NAND 
    nand_result <= not (operand_1 and operand_2_complemented);

    -- LLI 
    lli_result <= "0000000" & imm_9;

    -- 4. Result and Flag Multiplexing
    process(opcode, condition_met, add_result, nand_result, lli_result)
    begin
        -- Default assignments to prevent latches
        final_res_int <= (others => '0');
        final_c_int   <= '0';
        dest_reg_valid <= '0';
        dest_z_valid   <= '0';
        dest_c_valid   <= '0';

        case opcode is
            when "0001" => -- ADD Group 
                if condition_met = '1' then
                    final_res_int <= std_logic_vector(add_result(15 downto 0));
                    final_c_int   <= add_result(16);
                    dest_reg_valid <= '1';
                    dest_z_valid   <= '1';
                    dest_c_valid   <= '1';
                end if;

            when "0010" => -- NAND Group 
                if condition_met = '1' then
                    final_res_int <= nand_result;
                    dest_reg_valid <= '1';
                    dest_z_valid   <= '1';
                end if;

            when "0000" => -- ADI 
                final_res_int <= std_logic_vector(add_result(15 downto 0));
                final_c_int   <= add_result(16);
                dest_reg_valid <= '1';
                dest_z_valid   <= '1';
                dest_c_valid   <= '1';

            when "0011" => -- LLI 
                final_res_int  <= lli_result;
                dest_reg_valid <= '1';

            when others =>
                null;
        end case;
    end process;

    -- 5. Final Outputs
    result     <= final_res_int;
    c_flag_out <= final_c_int;
    z_flag_out <= '1' when final_res_int = x"0000" else '0';

    -- Wire passing for destination tags 
    dest_tag_reg_out <= dest_tag_reg_in & ALU_valid;
    dest_tag_z_out   <= dest_tag_z_in & ALU_valid;
    dest_tag_c_out   <= dest_tag_c_in & ALU_valid;

end architecture;