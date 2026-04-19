library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity ARF is
    generic (
        DATA_WIDTH : integer := 16;
        TAG_WIDTH  : integer := 5
    );
    port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        
        -- Dedicated R0 (PC) Ports
        R0_read_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        R0_write_en   : in  std_logic;
        R0_write_data : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Read Ports (Now includes Busy and Tag)
        read_addr_1   : in  std_logic_vector(2 downto 0);
        read_data_1   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        read_busy_1   : out std_logic;
        read_tag_1    : out std_logic_vector(TAG_WIDTH-1 downto 0);
        
        read_addr_2   : in  std_logic_vector(2 downto 0);
        read_data_2   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        read_busy_2   : out std_logic;
        read_tag_2    : out std_logic_vector(TAG_WIDTH-1 downto 0);

        read_addr_3   : in  std_logic_vector(2 downto 0);
        read_data_3   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        read_busy_3   : out std_logic;
        read_tag_3    : out std_logic_vector(TAG_WIDTH-1 downto 0);

        read_addr_4   : in  std_logic_vector(2 downto 0);
        read_data_4   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        read_busy_4   : out std_logic;
        read_tag_4    : out std_logic_vector(TAG_WIDTH-1 downto 0);
        
        -- Write Ports (Data, Busy, and Tag)
        write_en_1    : in  std_logic;
        write_addr_1  : in  std_logic_vector(2 downto 0);
        write_data_1  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        write_busy_1  : in  std_logic;
        write_tag_1   : in  std_logic_vector(TAG_WIDTH-1 downto 0);
        
        write_en_2    : in  std_logic;
        write_addr_2  : in  std_logic_vector(2 downto 0);
        write_data_2  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        write_busy_2  : in  std_logic;
        write_tag_2   : in  std_logic_vector(TAG_WIDTH-1 downto 0)
    );
end entity ARF;

architecture behavioral of ARF is
    type register_t is record
        data : std_logic_vector(DATA_WIDTH-1 downto 0);
        busy : std_logic;
        tag  : std_logic_vector(TAG_WIDTH-1 downto 0);
    end record;

    type reg_array is array (0 to 7) of register_t;
    signal registers : reg_array;
begin

    -- Synchronous Write Logic
 process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- Reset all registers to 0, not busy, and tag 0
                for i in 0 to 7 loop
                    registers(i).data <= (others => '0');
                    registers(i).busy <= '0';
                    registers(i).tag  <= (others => '0');
                end loop;
            else
                -- Write Port 1
						 if (write_en_1 = '1' and write_addr_1 /= "000") then
                    registers(to_integer(unsigned(write_addr_1))).data <= write_data_1;
                    registers(to_integer(unsigned(write_addr_1))).busy <= write_busy_1;
                    registers(to_integer(unsigned(write_addr_1))).tag  <= write_tag_1;
                end if;
                
                -- Write Port 2 (Overrides Port 1)
                if (write_en_2 = '1' and write_addr_2 /= "000") then
                    registers(to_integer(unsigned(write_addr_2))).data <= write_data_2;
                    registers(to_integer(unsigned(write_addr_2))).busy <= write_busy_2;
                    registers(to_integer(unsigned(write_addr_2))).tag  <= write_tag_2;
                end if;

                -- R0 High Priority Write
                -- Note: Usually R0 doesn't use the tag/busy logic in the same way 
                -- during fetch, but we keep it consistent.
                if R0_write_en = '1' then
                    registers(0).data <= R0_write_data;
                    -- Typically PC updates via R0_write are "committed" or "fetch-increments",
                    -- so we might want to clear the busy bit here depending on your pipeline.
                    registers(0).busy <= '0'; 
                end if;
            end if;
        end if;
    end process;

    -- Asynchronous Read Logic
    R0_read_data <= registers(0).data;

    -- Port 1
    read_data_1 <= registers(to_integer(unsigned(read_addr_1))).data;
    read_busy_1 <= registers(to_integer(unsigned(read_addr_1))).busy;
    read_tag_1  <= registers(to_integer(unsigned(read_addr_1))).tag;

    -- Port 2
    read_data_2 <= registers(to_integer(unsigned(read_addr_2))).data;
    read_busy_2 <= registers(to_integer(unsigned(read_addr_2))).busy;
    read_tag_2  <= registers(to_integer(unsigned(read_addr_2))).tag;

    -- Port 3
    read_data_3 <= registers(to_integer(unsigned(read_addr_3))).data;
    read_busy_3 <= registers(to_integer(unsigned(read_addr_3))).busy;
    read_tag_3  <= registers(to_integer(unsigned(read_addr_3))).tag;

    -- Port 4
    read_data_4 <= registers(to_integer(unsigned(read_addr_4))).data;
    read_busy_4 <= registers(to_integer(unsigned(read_addr_4))).busy;
    read_tag_4  <= registers(to_integer(unsigned(read_addr_4))).tag;

end architecture behavioral;


