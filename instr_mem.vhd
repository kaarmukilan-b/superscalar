library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Instr_Mem is -- byte addressing
    port (
        RA1, RA2 : in std_logic_vector(15 downto 0);
        RD1, RD2 : out std_logic_vector(15 downto 0)
    );
end entity;

-- little endian
architecture Instr_Mem_arch of Instr_Mem is

    -- Define the instruction memory as an array
    type Instr_Mem_arr is array (1023 downto 0) of std_logic_vector(7 downto 0);

    -- Initialize the memory with instructions
    signal Data : Instr_Mem_arr := (
        -- [Your initialized data remains the same]
        0 => "00000100", 1 => "01000010",
        -- ... rest of your initialization ...
        others => (others => '0')
    );

begin

    -- RD1: Read 16-bit word from RA1 (Little Endian: Data(RA+1) is High Byte, Data(RA) is Low Byte)
    -- Note: If your system is Little Endian, it's usually Data(n+1) & Data(n)
    -- If you want "Big Endian" style concatenation as in your original snippet:
    
    RD1 <= Data(to_integer(unsigned(RA1(9 downto 0)))) & 
           Data(to_integer(unsigned(RA1(9 downto 0))) + 1);

    -- RD2: Read 16-bit word from RA2
    RD2 <= Data(to_integer(unsigned(RA2(9 downto 0)))) & 
           Data(to_integer(unsigned(RA2(9 downto 0))) + 1);

end architecture;

--
--signal Data : Instr_Mem_arr := (
--	 --even - opcode Ra Rb Rc rest
--		  -- 0-1: ADI R2, R1, 2 (R2 is Rb, R1 is Ra) -> 0000 010 001 000010
--		  0 => "00000100", 1 => "01000010",
--		  
--        -- 2-3: ADA R1, R3, R4 (Ra, Rb, Rc) -> 0001 001 011 100 000
--        2 => "00010010", 3 => "11100000",
--		  
--        -- 4-5: ADA R5, R6, R5 -> 0001 101 110 101 000
--        4 => "00011011", 5 => "10101000",
--		  
--        -- 6-7: NDU R7, R1, R2 -> 0010 111 001 010 000
--        6 => "00101110", 7 => "01010000",
--		  
--        -- 8-9: LLI R4, 2 -> 0011 100 000000010
--        8 => "00111000", 9 => "00000010",
--		  
--		  
--		  
--		  -- 24-25: JRI R4, 3 -> 1111 001 000000011
--		  10 => "11111000", 11 => "00000000",
--		  
--        -- 10-11: ADA R3, R1, R2 -> 0001 011 001 010 000
--        24 => "00010110", 25 => "01010000",
--		  
--		  
--		  
--        -- 12-13: ADI R6, R5, 5 -> 0000 110 101 000101
--        12 => "00001101", 13 => "01000101",
--		  
--        -- 14-15: LLI R6, 1 -> 0011 110 000000001
--        14 => "00111100", 15 => "00000001",
--		  		  
--        -- 16-17: ADI R2, R2, 2 -> 0000 010 010 000011
--        16 => "00000100", 17 => "10000010",
--		  
--        -- 18-19: NDU R7, R3, R4 -> 0010 111 011 100 000
--        18 => "00101110", 19 => "11100000",
--		  
--		  -- works till here
--		  
--        -- 20-21: BEQ R1, R2, 1 -> 1000 001 010 000001
--        20 => "10000010", 21 => "10000001",
--		  
--        -- 22-23: ADA R5, R3, R4 -> 0001 101 011 100 000
--        22 => "00011010", 23 => "11100000",
--		  
--		  -- works till here
--		  
--        
--        -- 26-27: ADA R5, R5, R5 -> 0001 101 101 101 000
--        26 => "00011011", 27 => "01101000",
--		  
--        -- 28-29: ADA R6, R6, R6 -> 0001 110 110 110 000
--        28 => "00011101", 29 => "10110000",
--														
--		-- 30-31 : LM  R4 0110 100 0 11110000
--		  30 => "01101000", 31=> "00001111",
--														
--		  -- 32-33 SM R1 0111 001 0 0110 0000
--		  32 => "01110010" , 33 => "00000110",
--															
--		  --34-35 LM r1 0110 001 0 00000110
--		  34 => "01100010" , 35 => "01100000",
--		  
--        others => (others => '0') -- Default value for unused locations
--    );