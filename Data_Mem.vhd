library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Data_Mem is -- byte addressing
	port(
		RA, WA, WD : in std_logic_vector(15 downto 0); -- accesses RA,WA and RA+1, WA+1 addresses
		DM_en : in std_logic;
		clk : in std_logic;
		RD : out std_logic_vector(15 downto 0)
	);
end entity;

architecture Data_Mem_arch of Data_Mem is

	type Data_Mem_arr is array (1023 downto 0) of std_logic_vector(7 downto 0);

	signal Data : Data_Mem_arr := (
	-- initally all memory values are zeroes
		30 => "00000000", 31 => "00001111",
		32 => "00000000", 33 => "11110000",
		34 => "00001111", 35 => "00000000",
		36 => "11110000", 37 => "00000000",
		others => (others => '0')
	);

begin
    -- Use only the bottom 10 bits of RA to stay within 0-1023
    RD <= Data(to_integer(unsigned(RA(8 downto 0)))) & 
          Data(to_integer(unsigned(RA(8 downto 0))) + 1);

    DM_write_process : process(clk)
    begin
        if rising_edge(clk) then
            if DM_en = '1' then
                -- Use only the bottom 10 bits of WA
                Data(to_integer(unsigned(WA(8 downto 0))) + 1) <= WD(7 downto 0);
                Data(to_integer(unsigned(WA(8 downto 0))))     <= WD(15 downto 8);
            end if;
        end if;
    end process;
end Data_Mem_arch;
