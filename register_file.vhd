library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity register_file is
    port(   in1 : in STD_LOGIC_VECTOR(4 downto 0);
            out1 : out STD_LOGIC_VECTOR(4 downto 0) 
        );
end entity;

architecture struct of register_file is 

begin 
    out1 <= in1;
end architecture;