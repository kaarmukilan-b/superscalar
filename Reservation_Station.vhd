library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rs_types.all;

entity Reservation_Station is
    generic (
        NUM_ENTRIES : integer := 32
    );
    port (
        clk            : in  std_logic;
        reset          : in  std_logic; 
        
        -- Dispatch Ports
        dispatch_we_1  : in  std_logic;
        dispatch_idx_1 : in  std_logic_vector(4 downto 0);
        dispatch_in_1  : in  rs_entry_t;
        dispatch_we_2  : in  std_logic;
        dispatch_idx_2 : in  std_logic_vector(4 downto 0);
        dispatch_in_2  : in  rs_entry_t;
        
        -- Free Tag Outputs (Priority Encoder)
        free_tag_1     : out std_logic_vector(4 downto 0);
        free_tag_2     : out std_logic_vector(4 downto 0);
        
        -- Issue Ports (3 Ports)
        read_addr_1, read_addr_2, read_addr_3 : in  std_logic_vector(4 downto 0);
        read_row_1, read_row_2, read_row_3    : out rs_entry_t;
        v1_input, v2_input, v3_input          : in  std_logic; 
        
        -- Global Status
        rs_full        : out std_logic;
        ready_bits     : out std_logic_vector(NUM_ENTRIES-1 downto 0);

        -- 4 Data CDBs
        cdb1_valid, cdb2_valid, cdb3_valid, cdb4_valid : in  std_logic;
        cdb1_tag, cdb2_tag, cdb3_tag, cdb4_tag         : in  std_logic_vector(4 downto 0);
        cdb1_value, cdb2_value, cdb3_value, cdb4_value : in  std_logic_vector(15 downto 0);

        -- 2 Carry Flag CDBs
        cfcdb1_valid, cfcdb2_valid : in  std_logic;
        cfcdb1_tag, cfcdb2_tag     : in  std_logic_vector(4 downto 0);
        cfcdb1_value, cfcdb2_value : in  std_logic;

        -- 2 Zero Flag CDBs
        zfcdb1_valid, zfcdb2_valid : in  std_logic;
        zfcdb1_tag, zfcdb2_tag     : in  std_logic_vector(4 downto 0);
        zfcdb1_value, zfcdb2_value : in  std_logic
    );
end entity;

architecture rtl of Reservation_Station is
    signal rs_table : rs_array_t(0 to NUM_ENTRIES-1);
begin

    -- ==========================================
    -- 1. ASYNCHRONOUS READ LOGIC (3 Ports)
    -- ==========================================
    read_row_1 <= rs_table(to_integer(unsigned(read_addr_1)));
    read_row_2 <= rs_table(to_integer(unsigned(read_addr_2)));
    read_row_3 <= rs_table(to_integer(unsigned(read_addr_3)));

    -- ==========================================
    -- 2. COMBINATIONAL LOGIC (Ready, Full, Free Tags)
    -- ==========================================
    process(rs_table)
        variable free_count  : integer;
        variable found_first : boolean;
    begin
        free_count  := 0;
        found_first := false;
        free_tag_1  <= (others => '0');
        free_tag_2  <= (others => '0');
        
        for i in 0 to NUM_ENTRIES-1 loop
            -- Ready Bit
            if (rs_table(i).busy = '1') and 
               (rs_table(i).opr1_valid = '1') and (rs_table(i).opr2_valid = '1') and 
               (rs_table(i).carry_valid = '1') and (rs_table(i).zero_valid = '1') then
                ready_bits(i) <= '1';
            else
                ready_bits(i) <= '0';
            end if;

            -- Free Tags & RS_Full
            if rs_table(i).busy = '0' then
                free_count := free_count + 1;
                if not found_first then
                    free_tag_1 <= std_logic_vector(to_unsigned(i, 5));
                    found_first := true;
                elsif free_count = 2 then
                    free_tag_2 <= std_logic_vector(to_unsigned(i, 5));
                end if;
            end if;
        end loop;

        if free_count < 2 then rs_full <= '1'; else rs_full <= '0'; end if;
    end process;

    -- ==========================================
    -- 3. SYNCHRONOUS UPDATE & SNOOPING LOGIC
    -- ==========================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                for i in 0 to NUM_ENTRIES-1 loop
                    rs_table(i).busy <= '0';
                end loop;
            else
                -- A. CDB SNOOPING
                for i in 0 to NUM_ENTRIES-1 loop
                    if rs_table(i).busy = '1' then
                        
                        -- Snoop Operand 1 (4 Data CDBs)
                        if rs_table(i).opr1_valid = '0' then
                            if cdb1_valid = '1' and rs_table(i).opr1_tag = cdb1_tag then
                                rs_table(i).opr1 <= cdb1_value; rs_table(i).opr1_valid <= '1';
                            elsif cdb2_valid = '1' and rs_table(i).opr1_tag = cdb2_tag then
                                rs_table(i).opr1 <= cdb2_value; rs_table(i).opr1_valid <= '1';
                            elsif cdb3_valid = '1' and rs_table(i).opr1_tag = cdb3_tag then
                                rs_table(i).opr1 <= cdb3_value; rs_table(i).opr1_valid <= '1';
                            elsif cdb4_valid = '1' and rs_table(i).opr1_tag = cdb4_tag then
                                rs_table(i).opr1 <= cdb4_value; rs_table(i).opr1_valid <= '1';
                            end if;
                        end if;

                        -- Snoop Operand 2 (4 Data CDBs)
                        if rs_table(i).opr2_valid = '0' then
                            if cdb1_valid = '1' and rs_table(i).opr2_tag = cdb1_tag then
                                rs_table(i).opr2 <= cdb1_value; rs_table(i).opr2_valid <= '1';
                            elsif cdb2_valid = '1' and rs_table(i).opr2_tag = cdb2_tag then
                                rs_table(i).opr2 <= cdb2_value; rs_table(i).opr2_valid <= '1';
                            elsif cdb3_valid = '1' and rs_table(i).opr2_tag = cdb3_tag then
                                rs_table(i).opr2 <= cdb3_value; rs_table(i).opr2_valid <= '1';
                            elsif cdb4_valid = '1' and rs_table(i).opr2_tag = cdb4_tag then
                                rs_table(i).opr2 <= cdb4_value; rs_table(i).opr2_valid <= '1';
                            end if;
                        end if;

                        -- Snoop Carry Flag (2 Carry CDBs)
                        if rs_table(i).carry_valid = '0' then
                            if cfcdb1_valid = '1' and rs_table(i).carry_tag = cfcdb1_tag then
                                rs_table(i).carry_value <= cfcdb1_value; rs_table(i).carry_valid <= '1';
                            elsif cfcdb2_valid = '1' and rs_table(i).carry_tag = cfcdb2_tag then
                                rs_table(i).carry_value <= cfcdb2_value; rs_table(i).carry_valid <= '1';
                            end if;
                        end if;

                        -- Snoop Zero Flag (2 Zero CDBs)
                        if rs_table(i).zero_valid = '0' then
                            if zfcdb1_valid = '1' and rs_table(i).zero_tag = zfcdb1_tag then
                                rs_table(i).zero_value <= zfcdb1_value; rs_table(i).zero_valid <= '1';
                            elsif zfcdb2_valid = '1' and rs_table(i).zero_tag = zfcdb2_tag then
                                rs_table(i).zero_value <= zfcdb2_value; rs_table(i).zero_valid <= '1';
                            end if;
                        end if;
                        
                    end if;
                end loop;

                -- B. ISSUE LOGIC (3 Ports)
                if v1_input = '1' then rs_table(to_integer(unsigned(read_addr_1))).busy <= '0'; end if;
                if v2_input = '1' then rs_table(to_integer(unsigned(read_addr_2))).busy <= '0'; end if;
                if v3_input = '1' then rs_table(to_integer(unsigned(read_addr_3))).busy <= '0'; end if;

                -- C. DISPATCH LOGIC
                if dispatch_we_1 = '1' then rs_table(to_integer(unsigned(dispatch_idx_1))) <= dispatch_in_1; end if;
                if dispatch_we_2 = '1' then rs_table(to_integer(unsigned(dispatch_idx_2))) <= dispatch_in_2; end if;
                
            end if;
        end if;
    end process;

end architecture rtl;


