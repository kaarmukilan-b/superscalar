library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Flag Rename Register File (FRRF) for Carry and Zero Flags
entity RRF_flags is
 port (
	  clk, reset                          : in std_logic;
	  
	  -- --- CARRY FLAG INTERFACE ---
	  c_write_tag_1, c_write_tag_2        : in std_logic_vector(4 downto 0);
	  c_write_1_valid, c_write_2_valid    : in std_logic;
	  c_write_val_1, c_write_val_2        : in std_logic; -- 1-bit value
	  c_free_tag_1_out, c_free_tag_2_out  : out std_logic_vector(4 downto 0);
	  c_fill_free_1, c_fill_free_2        : in std_logic;
	  c_full                              : out std_logic;
	  c_release_tag_1, c_release_tag_2    : in std_logic_vector(4 downto 0);
	  c_release_1_valid, c_release_2_valid: in std_logic;
	  c_read_tag_1, c_read_tag_2          : in std_logic_vector(4 downto 0);
	  c_read_val_1, c_read_val_2          : out std_logic;
	  c_read_busy_1, c_read_busy_2        : out std_logic;
	  c_read_valid_1, c_read_valid_2      : out std_logic;

	  -- --- ZERO FLAG INTERFACE ---
	  z_write_tag_1, z_write_tag_2        : in std_logic_vector(4 downto 0);
	  z_write_1_valid, z_write_2_valid    : in std_logic;
	  z_write_val_1, z_write_val_2        : in std_logic; -- 1-bit value
	  z_free_tag_1_out, z_free_tag_2_out  : out std_logic_vector(4 downto 0);
	  z_fill_free_1, z_fill_free_2        : in std_logic;
	  z_full                              : out std_logic;
	  z_release_tag_1, z_release_tag_2    : in std_logic_vector(4 downto 0);
	  z_release_1_valid, z_release_2_valid: in std_logic;
	  z_read_tag_1, z_read_tag_2          : in std_logic_vector(4 downto 0);
	  z_read_val_1, z_read_val_2          : out std_logic;
	  z_read_busy_1, z_read_busy_2        : out std_logic;
	  z_read_valid_1, z_read_valid_2      : out std_logic
 );
end entity;

architecture rtl of RRF_flags is
 -- Storage for Carry Bank
 signal c_busy  : std_logic_vector(31 downto 0) := (others => '0');
 signal c_valid : std_logic_vector(31 downto 0) := (others => '0');
 signal c_value : std_logic_vector(31 downto 0) := (others => '0');

 -- Storage for Zero Bank
 signal z_busy  : std_logic_vector(31 downto 0) := (others => '0');
 signal z_valid : std_logic_vector(31 downto 0) := (others => '0');
 signal z_value : std_logic_vector(31 downto 0) := (others => '0');

 -- Internal signals for priority encoders
 signal c_mask1, c_mask2 : std_logic_vector(31 downto 0);
 signal z_mask1, z_mask2 : std_logic_vector(31 downto 0);
 
begin

 ---------------------------------------------------------------------------
 -- 1. PRIORITY ENCODER LOGIC (CARRY)
 ---------------------------------------------------------------------------
 process(c_busy)
 begin
	  c_mask1 <= (others => '0');
	  for i in 0 to 31 loop
			if c_busy(i) = '0' then
				 c_mask1(i) <= '1'; exit;
			end if;
	  end loop;
 end process;

 process(c_busy, c_mask1)
 begin
	  c_mask2 <= (others => '0');
	  for i in 0 to 31 loop
			if c_busy(i) = '0' and c_mask1(i) = '0' then
				 c_mask2(i) <= '1'; exit;
			end if;
	  end loop;
 end process;

 -- Mapping Carry Free Tags
 process(c_mask1, c_mask2)
 begin
	  c_free_tag_1_out <= (others => '0');
	  c_free_tag_2_out <= (others => '0');
	  for i in 0 to 31 loop
			if c_mask1(i) = '1' then c_free_tag_1_out <= std_logic_vector(to_unsigned(i, 5)); end if;
			if c_mask2(i) = '1' then c_free_tag_2_out <= std_logic_vector(to_unsigned(i, 5)); end if;
	  end loop;
 end process;
 
 c_full <= '1' when (unsigned(c_mask2) = 0) else '0';

 ---------------------------------------------------------------------------
 -- 2. PRIORITY ENCODER LOGIC (ZERO)
 ---------------------------------------------------------------------------
 process(z_busy)
 begin
	  z_mask1 <= (others => '0');
	  for i in 0 to 31 loop
			if z_busy(i) = '0' then
				 z_mask1(i) <= '1'; exit;
			end if;
	  end loop;
 end process;

 process(z_busy, z_mask1)
 begin
	  z_mask2 <= (others => '0');
	  for i in 0 to 31 loop
			if z_busy(i) = '0' and z_mask1(i) = '0' then
				 z_mask2(i) <= '1'; exit;
			end if;
	  end loop;
 end process;

 -- Mapping Zero Free Tags
 process(z_mask1, z_mask2)
 begin
	  z_free_tag_1_out <= (others => '0');
	  z_free_tag_2_out <= (others => '0');
	  for i in 0 to 31 loop
			if z_mask1(i) = '1' then z_free_tag_1_out <= std_logic_vector(to_unsigned(i, 5)); end if;
			if z_mask2(i) = '1' then z_free_tag_2_out <= std_logic_vector(to_unsigned(i, 5)); end if;
	  end loop;
 end process;

 z_full <= '1' when (unsigned(z_mask2) = 0) else '0';

 ---------------------------------------------------------------------------
 -- 3. ASYNCHRONOUS READ PORTS (C and Z)
 ---------------------------------------------------------------------------
 
 -- C Port 1
 c_read_val_1   <= c_write_val_1 when (c_write_1_valid = '1' and c_write_tag_1 = c_read_tag_1) else
						 c_write_val_2 when (c_write_2_valid = '1' and c_write_tag_2 = c_read_tag_1) else
						 c_value(to_integer(unsigned(c_read_tag_1)));
 
 c_read_valid_1 <= '1' when (c_write_1_valid = '1' and c_write_tag_1 = c_read_tag_1) else
						 '1' when (c_write_2_valid = '1' and c_write_tag_2 = c_read_tag_1) else
						 c_valid(to_integer(unsigned(c_read_tag_1)));

 c_read_busy_1  <= c_busy(to_integer(unsigned(c_read_tag_1)));

 -- C Port 2
 c_read_val_2   <= c_write_val_1 when (c_write_1_valid = '1' and c_write_tag_1 = c_read_tag_2) else
						 c_write_val_2 when (c_write_2_valid = '1' and c_write_tag_2 = c_read_tag_2) else
						 c_value(to_integer(unsigned(c_read_tag_2)));
 
 c_read_valid_2 <= '1' when (c_write_1_valid = '1' and c_write_tag_1 = c_read_tag_2) else
						 '1' when (c_write_2_valid = '1' and c_write_tag_2 = c_read_tag_2) else
						 c_valid(to_integer(unsigned(c_read_tag_2)));

 c_read_busy_2  <= c_busy(to_integer(unsigned(c_read_tag_2)));


 -- === ZERO FLAG READ PORTS ===

 -- Z Port 1
 z_read_val_1   <= z_write_val_1 when (z_write_1_valid = '1' and z_write_tag_1 = z_read_tag_1) else
						 z_write_val_2 when (z_write_2_valid = '1' and z_write_tag_2 = z_read_tag_1) else
						 z_value(to_integer(unsigned(z_read_tag_1)));
 
 z_read_valid_1 <= '1' when (z_write_1_valid = '1' and z_write_tag_1 = z_read_tag_1) else
						 '1' when (z_write_2_valid = '1' and z_write_tag_2 = z_read_tag_1) else
						 z_valid(to_integer(unsigned(z_read_tag_1)));

 z_read_busy_1  <= z_busy(to_integer(unsigned(z_read_tag_1)));

 -- Z Port 2
 z_read_val_2   <= z_write_val_1 when (z_write_1_valid = '1' and z_write_tag_1 = z_read_tag_2) else
						 z_write_val_2 when (z_write_2_valid = '1' and z_write_tag_2 = z_read_tag_2) else
						 z_value(to_integer(unsigned(z_read_tag_2)));
 
 z_read_valid_2 <= '1' when (z_write_1_valid = '1' and z_write_tag_1 = z_read_tag_2) else
						 '1' when (z_write_2_valid = '1' and z_write_tag_2 = z_read_tag_2) else
						 z_valid(to_integer(unsigned(z_read_tag_2)));

 z_read_busy_2  <= z_busy(to_integer(unsigned(z_read_tag_2)));
 ---------------------------------------------------------------------------
 -- 4. SYNCHRONOUS UPDATE LOGIC
 ---------------------------------------------------------------------------
 process(clk)
	  variable c_f1, c_f2, z_f1, z_f2 : integer;
 begin
	  if rising_edge(clk) then
			if reset = '1' then
				 c_busy <= (others => '0'); c_valid <= (others => '0');
				 z_busy <= (others => '0'); z_valid <= (others => '0');
			else
				 -- Temporary variables for indices to keep code clean
				 c_f1 := to_integer(unsigned(c_mask1)); -- Logic handled via masks
				 
				 -- --- CARRY UPDATES ---
				 -- Release
				 if c_release_1_valid = '1' then c_busy(to_integer(unsigned(c_release_tag_1))) <= '0'; c_valid(to_integer(unsigned(c_release_tag_1))) <= '0'; end if;
				 if c_release_2_valid = '1' then c_busy(to_integer(unsigned(c_release_tag_2))) <= '0'; c_valid(to_integer(unsigned(c_release_tag_2))) <= '0'; end if;
				 -- Fill (Reserve tag)
				 if c_fill_free_1 = '1' then 
					  for i in 0 to 31 loop if c_mask1(i) = '1' then c_busy(i) <= '1'; c_valid(i) <= '0'; exit; end if; end loop;
				 end if;
				 if c_fill_free_2 = '1' then 
					  for i in 0 to 31 loop if c_mask2(i) = '1' then c_busy(i) <= '1'; c_valid(i) <= '0'; exit; end if; end loop;
				 end if;
				 -- Write (Update value)
				 if c_write_1_valid = '1' then c_value(to_integer(unsigned(c_write_tag_1))) <= c_write_val_1; c_valid(to_integer(unsigned(c_write_tag_1))) <= '1'; end if;
				 if c_write_2_valid = '1' then c_value(to_integer(unsigned(c_write_tag_2))) <= c_write_val_2; c_valid(to_integer(unsigned(c_write_tag_2))) <= '1'; end if;

				 -- --- ZERO UPDATES ---
				 -- Release
				 if z_release_1_valid = '1' then z_busy(to_integer(unsigned(z_release_tag_1))) <= '0'; z_valid(to_integer(unsigned(z_release_tag_1))) <= '0'; end if;
				 if z_release_2_valid = '1' then z_busy(to_integer(unsigned(z_release_tag_2))) <= '0'; z_valid(to_integer(unsigned(z_release_tag_2))) <= '0'; end if;
				 -- Fill (Reserve tag)
				 if z_fill_free_1 = '1' then 
					  for i in 0 to 31 loop if z_mask1(i) = '1' then z_busy(i) <= '1'; z_valid(i) <= '0'; exit; end if; end loop;
				 end if;
				 if z_fill_free_2 = '1' then 
					  for i in 0 to 31 loop if z_mask2(i) = '1' then z_busy(i) <= '1'; z_valid(i) <= '0'; exit; end if; end loop;
				 end if;
				 -- Write (Update value)
				 if z_write_1_valid = '1' then z_value(to_integer(unsigned(z_write_tag_1))) <= z_write_val_1; z_valid(to_integer(unsigned(z_write_tag_1))) <= '1'; end if;
				 if z_write_2_valid = '1' then z_value(to_integer(unsigned(z_write_tag_2))) <= z_write_val_2; z_valid(to_integer(unsigned(z_write_tag_2))) <= '1'; end if;
			end if;
	  end if;
 end process;

end architecture;