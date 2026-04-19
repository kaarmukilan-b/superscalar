library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity instr_buffer is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic; -- Active high
        
        -- Write Enables
        write_en_1              : in  std_logic;
        write_en_2              : in  std_logic;
        
        -- Input: Instruction 1 Slot
        in_Instr1               : in  std_logic_vector(15 downto 0);
        in_PC1                  : in  std_logic_vector(15 downto 0);
        in_PCnext_predicted1    : in  std_logic_vector(15 downto 0);
        in_valid1               : in  std_logic;
        
        -- Input: Instruction 2 Slot
        in_Instr2               : in  std_logic_vector(15 downto 0);
        in_PC2                  : in  std_logic_vector(15 downto 0);
        in_PCnext_predicted2    : in  std_logic_vector(15 downto 0);
        in_valid2               : in  std_logic;

        -- Output: Instruction 1 Slot
        out_Instr1              : out std_logic_vector(15 downto 0);
        out_PC1                 : out std_logic_vector(15 downto 0);
        out_PCnext_predicted1   : out std_logic_vector(15 downto 0);
        out_valid1              : out std_logic;
        
        -- Output: Instruction 2 Slot
        out_Instr2              : out std_logic_vector(15 downto 0);
        out_PC2                 : out std_logic_vector(15 downto 0);
        out_PCnext_predicted2   : out std_logic_vector(15 downto 0);
        out_valid2              : out std_logic
    );
end entity instr_buffer;

architecture rtl of instr_buffer is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- Clear all outputs on reset
                out_Instr1            <= (others => '0');
                out_PC1               <= (others => '0');
                out_PCnext_predicted1 <= (others => '0');
                out_valid1            <= '0';
                
                out_Instr2            <= (others => '0');
                out_PC2               <= (others => '0');
                out_PCnext_predicted2 <= (others => '0');
                out_valid2            <= '0';
            else
                -- Latch Instruction 1 if enabled
                if write_en_1 = '1' then
                    out_Instr1            <= in_Instr1;
                    out_PC1               <= in_PC1;
                    out_PCnext_predicted1 <= in_PCnext_predicted1;
                    out_valid1            <= in_valid1;
                end if;
                
                -- Latch Instruction 2 if enabled
                if write_en_2 = '1' then
                    out_Instr2            <= in_Instr2;
                    out_PC2               <= in_PC2;
                    out_PCnext_predicted2 <= in_PCnext_predicted2;
                    out_valid2            <= in_valid2;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;

