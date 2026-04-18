library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Rename register file
entity RRF is -- a row contains busy bit, value, valid 
	port ( 
		clk , reset 							: in std_logic;
		write_tag_in_1, write_tag_in_2 	: in std_logic_vector(4 downto 0); -- writing value to a tag (busy = 1)
		write_1_valid, write_2_valid 		: in std_logic;							-- valid for above write
		write_value_1, write_value_2 		: in std_logic_vector(15 downto 0);	-- value for above write
		free_tag_1_out, free_tag_2_out	: out std_logic_vector(4 downto 0); -- it gives out address of any free row 
		fill_free_tag_1, fill_free_tag_2	: in std_logic; -- command bit to fill the  free row , by pulling busy = 1
		RRF_filled								: out std_logic; -- if two free rows are not available ( it will halt the intruction fetch)
		release_tag_1, release_tag_2		: in	std_logic_vector(4 downto 0); -- after writing back to ARF, this address says the RRF row is now free, busy = 0
		release_tag_1_valid, release_tag_2_valid		: in	std_logic; -- validity check for the release_tag
		read_tag_1, read_tag_2, read_tag_3, read_tag_4 : in  std_logic_vector(4 downto 0); -- to read from rrf
		read_value_1, read_value_2, read_value_3, read_value_4 : out std_logic_vector(15 downto 0); -- value
		read_busy_1, read_busy_2, read_busy_3, read_busy_4 	 : out std_logic;								-- give the value in the row
		read_valid_1, read_valid_2, read_valid_3, read_valid_4 : out std_logic								-- give the value in the row
	);
end entity;

architecture struct of RRF is 
    
    signal busy  : std_logic_vector(31 downto 0) := (others => '0');
    signal valid : std_logic_vector(31 downto 0) := (others => '0');
    type array32 is array (31 downto 0) of std_logic_vector(15 downto 0);
    signal value_storage : array32 := (others => (others => '0'));

    signal first_free_mask : std_logic_vector(31 downto 0);
    signal second_free_mask : std_logic_vector(31 downto 0);
    signal free_tag_1,free_tag_2 : std_logic_vector(4 downto 0);
begin
		
		free_tag_1_out <= free_tag_1;
		free_tag_2_out <= free_tag_2;
    -- 1. COMBINATIONAL PRIORITY ENCODER (For Free Tags)
    -- This logic finds the first zero in the 'busy' vector
    process(busy)
    begin
        first_free_mask <= (others => '0');
        for i in 0 to 31 loop
            if busy(i) = '0' then
                first_free_mask(i) <= '1';
                exit; 
            end if;
        end loop;
    end process;

    -- Generate mask for the second free bit (ignores the first one)
    process(busy, first_free_mask)
    begin
        second_free_mask <= (others => '0');
        for i in 0 to 31 loop
            -- A bit is a candidate if it's not busy AND wasn't picked by mask 1
            if busy(i) = '0' and first_free_mask(i) = '0' then
                second_free_mask(i) <= '1';
                exit;
            end if;
        end loop;
    end process;

    -- Convert masks to 5-bit tags
    process(first_free_mask, second_free_mask)
    begin
        free_tag_1 <= (others => '0');
        free_tag_2 <= (others => '0');
        for i in 0 to 31 loop
            if first_free_mask(i) = '1' then
                free_tag_1 <= std_logic_vector(to_unsigned(i, 5));
            end if;
            if second_free_mask(i) = '1' then
                free_tag_2 <= std_logic_vector(to_unsigned(i, 5));
            end if;
        end loop;
    end process;

    -- RRF_filled is active (1) if we don't have a valid bit in the second mask
    RRF_filled <= '0' when (unsigned(second_free_mask) /= 0) else '1';
    
	 -------------------------------------------------------------------------
    -- 3. ASYNCHRONOUS READ PORTS (With Write-Back Bypass)
    -------------------------------------------------------------------------
    -- For each read port, we check:
    -- 1. Is there a match with write_tag_in_1? If so, bypass write_value_1.
    -- 2. Is there a match with write_tag_in_2? If so, bypass write_value_2.
    -- 3. Otherwise, read from the internal storage.
    
    -- Port 1
    read_value_1 <= write_value_1 when (write_1_valid = '1' and write_tag_in_1 = read_tag_1) else
                    write_value_2 when (write_2_valid = '1' and write_tag_in_2 = read_tag_1) else
                    value_storage(to_integer(unsigned(read_tag_1)));
                    
    read_valid_1 <= '1' when (write_1_valid = '1' and write_tag_in_1 = read_tag_1) else
                    '1' when (write_2_valid = '1' and write_tag_in_2 = read_tag_1) else
                    valid(to_integer(unsigned(read_tag_1)));

    read_busy_1  <= busy(to_integer(unsigned(read_tag_1))); -- Busy bit doesn't change on write-back

    -- Port 2
    read_value_2 <= write_value_1 when (write_1_valid = '1' and write_tag_in_1 = read_tag_2) else
                    write_value_2 when (write_2_valid = '1' and write_tag_in_2 = read_tag_2) else
                    value_storage(to_integer(unsigned(read_tag_2)));
                    
    read_valid_2 <= '1' when (write_1_valid = '1' and write_tag_in_1 = read_tag_2) else
                    '1' when (write_2_valid = '1' and write_tag_in_2 = read_tag_2) else
                    valid(to_integer(unsigned(read_tag_2)));

    read_busy_2  <= busy(to_integer(unsigned(read_tag_2)));

    -- Port 3
    read_value_3 <= write_value_1 when (write_1_valid = '1' and write_tag_in_1 = read_tag_3) else
                    write_value_2 when (write_2_valid = '1' and write_tag_in_2 = read_tag_3) else
                    value_storage(to_integer(unsigned(read_tag_3)));
                    
    read_valid_3 <= '1' when (write_1_valid = '1' and write_tag_in_1 = read_tag_3) else
                    '1' when (write_2_valid = '1' and write_tag_in_2 = read_tag_3) else
                    valid(to_integer(unsigned(read_tag_3)));

    read_busy_3  <= busy(to_integer(unsigned(read_tag_3)));

    -- Port 4
    read_value_4 <= write_value_1 when (write_1_valid = '1' and write_tag_in_1 = read_tag_4) else
                    write_value_2 when (write_2_valid = '1' and write_tag_in_2 = read_tag_4) else
                    value_storage(to_integer(unsigned(read_tag_4)));
                    
    read_valid_4 <= '1' when (write_1_valid = '1' and write_tag_in_1 = read_tag_4) else
                    '1' when (write_2_valid = '1' and write_tag_in_2 = read_tag_4) else
                    valid(to_integer(unsigned(read_tag_4)));

    read_busy_4  <= busy(to_integer(unsigned(read_tag_4)));
--	 3. ASYNCHRONOUS READ PORTS
--    read_value_1 <= value_storage(to_integer(unsigned(read_tag_1)));
--    read_valid_1 <= valid(to_integer(unsigned(read_tag_1)));
--    read_busy_1  <= busy(to_integer(unsigned(read_tag_1)));
--	 
--    read_value_2 <= value_storage(to_integer(unsigned(read_tag_2)));
--    read_valid_2 <= valid(to_integer(unsigned(read_tag_2)));
--    read_busy_2  <= busy(to_integer(unsigned(read_tag_2)));
--	 
--    read_value_3 <= value_storage(to_integer(unsigned(read_tag_3)));
--    read_valid_3 <= valid(to_integer(unsigned(read_tag_3)));
--    read_busy_3  <= busy(to_integer(unsigned(read_tag_3)));
--	 
--    read_value_4 <= value_storage(to_integer(unsigned(read_tag_4)));
--    read_valid_4 <= valid(to_integer(unsigned(read_tag_4)));
--	   read_busy_4  <= busy(to_integer(unsigned(read_tag_4)));
--	 
    -- 4. SYNCHRONOUS UPDATE LOGIC
    -- You will need to map 'clk' and 'rst' in your top level.
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                busy  <= (others => '0');
                valid <= (others => '0');
            else
                -- PRIORITY: Release (from Commit stage)
                if release_tag_1_valid = '1' then
                    busy(to_integer(unsigned(release_tag_1))) <= '0';
                    valid(to_integer(unsigned(release_tag_1))) <= '0';
                end if;
                if release_tag_2_valid = '1' then
                    busy(to_integer(unsigned(release_tag_2))) <= '0';
                    valid(to_integer(unsigned(release_tag_2))) <= '0';
                end if;

                -- PRIORITY: Fill (from Dispatch stage)
                if fill_free_tag_1 = '1' then
                    busy(to_integer(unsigned(free_tag_1))) <= '1';
                    valid(to_integer(unsigned(free_tag_1))) <= '0';
                end if;
                if fill_free_tag_2 = '1' then
                    busy(to_integer(unsigned(free_tag_2))) <= '1';
                    valid(to_integer(unsigned(free_tag_2))) <= '0';
                end if;

                -- PRIORITY: Write (from Write-back stage)
                if write_1_valid = '1' then
                    value_storage(to_integer(unsigned(write_tag_in_1))) <= write_value_1;
                    valid(to_integer(unsigned(write_tag_in_1))) <= '1';
                end if;
                if write_2_valid = '1' then
                    value_storage(to_integer(unsigned(write_tag_in_2))) <= write_value_2;
                    valid(to_integer(unsigned(write_tag_in_2))) <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture;