library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder_2 is
    port (input_16  : in  std_logic_vector(15 downto 0); output_16 : out std_logic_vector(15 downto 0) );
end entity;

architecture structural of adder_2 is

    signal result_unsigned : unsigned(15 downto 0);

begin

    result_unsigned <= unsigned(input_16) + 2;
    
    output_16 <= std_logic_vector(result_unsigned);

end architecture;