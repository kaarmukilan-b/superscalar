library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity scheduler_buffer is
    Port (clk,en,reset : in  STD_LOGIC;      
			  D      : in  STD_LOGIC_VECTOR(196 downto 0); 
			  Q      : out STD_LOGIC_VECTOR(196 downto 0)  );
end entity;

architecture Behavioral of scheduler_buffer is
    signal Q_reg : STD_LOGIC_VECTOR(196 downto 0) := (others => '0');
begin
   process(clk)
	begin
	if rising_edge(clk) then
		if reset = '1' then
			Q_reg <= (others => '0');
		elsif en = '1' then
			Q_reg <= D; 	
		end if;
	end if;
   end process;

    Q <= Q_reg; 
end Behavioral;
