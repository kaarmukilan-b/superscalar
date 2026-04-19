library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity CCF is
    generic (
        TAG_WIDTH : integer := 5
    );
    port (
        clk          : in  std_logic;
        reset        : in  std_logic;

        -- Read Port (Continuous Output)
        C_data_out   : out std_logic;
        C_busy_out   : out std_logic;
        C_tag_out    : out std_logic_vector(TAG_WIDTH-1 downto 0);

        Z_data_out   : out std_logic;
        Z_busy_out   : out std_logic;
        Z_tag_out    : out std_logic_vector(TAG_WIDTH-1 downto 0);

        -- Write Port 1 (Dispatch/Commit Port A)
        C_write_en_1 : in  std_logic;
        C_data_in_1  : in  std_logic;
        C_busy_in_1  : in  std_logic;
        C_tag_in_1   : in  std_logic_vector(TAG_WIDTH-1 downto 0);

        Z_write_en_1 : in  std_logic;
        Z_data_in_1  : in  std_logic;
        Z_busy_in_1  : in  std_logic;
        Z_tag_in_1   : in  std_logic_vector(TAG_WIDTH-1 downto 0);

        -- Write Port 2 (Dispatch/Commit Port B - Higher Priority)
        C_write_en_2 : in  std_logic;
        C_data_in_2  : in  std_logic;
        C_busy_in_2  : in  std_logic;
        C_tag_in_2   : in  std_logic_vector(TAG_WIDTH-1 downto 0);

        Z_write_en_2 : in  std_logic;
        Z_data_in_2  : in  std_logic;
        Z_busy_in_2  : in  std_logic;
        Z_tag_in_2   : in  std_logic_vector(TAG_WIDTH-1 downto 0)
    );
end entity CCF;

architecture behavioral of CCF is
    type flag_t is record
        data : std_logic;
        busy : std_logic;
        tag  : std_logic_vector(TAG_WIDTH-1 downto 0);
    end record;

    signal carry_flag : flag_t;
    signal zero_flag  : flag_t;
begin

    -- Synchronous Write Logic
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                carry_flag <= ('0', '0', (others => '0'));
                zero_flag  <= ('0', '0', (others => '0'));
            else
                -- Independent Carry Logic
                if C_write_en_2 = '1' then
                    carry_flag <= (C_data_in_2, C_busy_in_2, C_tag_in_2);
                elsif C_write_en_1 = '1' then
                    carry_flag <= (C_data_in_1, C_busy_in_1, C_tag_in_1);
                end if;

                -- Independent Zero Logic
                if Z_write_en_2 = '1' then
                    zero_flag <= (Z_data_in_2, Z_busy_in_2, Z_tag_in_2);
                elsif Z_write_en_1 = '1' then
                    zero_flag <= (Z_data_in_1, Z_busy_in_1, Z_tag_in_1);
                end if;
            end if;
        end if;
    end process;

    -- Asynchronous Continuous Read
    C_data_out <= carry_flag.data;
    C_busy_out <= carry_flag.busy;
    C_tag_out  <= carry_flag.tag;

    Z_data_out <= zero_flag.data;
    Z_busy_out <= zero_flag.busy;
    Z_tag_out  <= zero_flag.tag;

end architecture behavioral;

