library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rs_types.all; -- Re-using your RS record type

entity Load_Store_Queue is
    generic (
        QUEUE_DEPTH : integer := 16; -- Power of 2 is best for circular buffers
        PTR_WIDTH   : integer := 4   -- log2(QUEUE_DEPTH)
    );
    port (
        clk            : in  std_logic;
        reset          : in  std_logic; 
        
        -- Dispatch Ports (Writing to Tail)
        dispatch_we_1  : in  std_logic;
        dispatch_in_1  : in  rs_entry_t;
        dispatch_we_2  : in  std_logic;
        dispatch_in_2  : in  rs_entry_t;
        
        -- Status Outputs
        lsq_full       : out std_logic;
        lsq_empty      : out std_logic;
        
        -- Issue/Execute Ports (Reading from Head)
        -- Provide the head element so the Memory Execution Unit can check if it's ready
        head_data      : out rs_entry_t;
        head_ready     : out std_logic;
        
        -- External signal to pop the head element (from Memory Exec Unit or Commit)
        pop_head       : in  std_logic; 

        -- 4 Data CDBs (For snooping base addresses and store data)
        cdb1_valid, cdb2_valid, cdb3_valid, cdb4_valid : in  std_logic;
        cdb1_tag, cdb2_tag, cdb3_tag, cdb4_tag         : in  std_logic_vector(4 downto 0);
        cdb1_value, cdb2_value, cdb3_value, cdb4_value : in  std_logic_vector(15 downto 0);
        
        -- Assuming Memory instructions don't depend on flags in your ISA, 
        -- but keeping the ports if your record requires them to be cleared.
        cfcdb1_valid, cfcdb2_valid : in  std_logic;
        cfcdb1_tag, cfcdb2_tag     : in  std_logic_vector(4 downto 0);
        cfcdb1_value, cfcdb2_value : in  std_logic;
        zfcdb1_valid, zfcdb2_valid : in  std_logic;
        zfcdb1_tag, zfcdb2_tag     : in  std_logic_vector(4 downto 0);
        zfcdb1_value, zfcdb2_value : in  std_logic
    );
end entity Load_Store_Queue;

architecture rtl of Load_Store_Queue is
    
    signal lsq_table : rs_array_t(0 to QUEUE_DEPTH-1);
    
    -- Circular Buffer Pointers
    signal head_ptr : unsigned(PTR_WIDTH-1 downto 0);
    signal tail_ptr : unsigned(PTR_WIDTH-1 downto 0);
    signal count    : unsigned(PTR_WIDTH downto 0); -- Needs extra bit to count up to QUEUE_DEPTH
    
    -- Internal signals
    signal is_full  : std_logic;
    signal is_empty : std_logic;

begin

    -- Status Signals
    is_full   <= '1' when count >= (QUEUE_DEPTH - 1) else '0'; -- Leave buffer for 2-way dispatch
    is_empty  <= '1' when count = 0 else '0';
    
    lsq_full  <= is_full;
    lsq_empty <= is_empty;

    -- Output the current head
    head_data <= lsq_table(to_integer(head_ptr));
    
    -- Combinational ready check for the head instruction
    head_ready <= '1' when (lsq_table(to_integer(head_ptr)).busy = '1') and 
                           (lsq_table(to_integer(head_ptr)).opr1_valid = '1') and 
                           (lsq_table(to_integer(head_ptr)).opr2_valid = '1') else '0';

    -- Synchronous Logic
    process(clk)
        variable next_tail : unsigned(PTR_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                head_ptr <= (others => '0');
                tail_ptr <= (others => '0');
                count    <= (others => '0');
                for i in 0 to QUEUE_DEPTH-1 loop
                    lsq_table(i).busy <= '0';
                end loop;
            else
                
                -------------------------------------------------
                -- 1. SNOOPING LOGIC (Wakeup values in the queue)
                -------------------------------------------------
                for i in 0 to QUEUE_DEPTH-1 loop
                    if lsq_table(i).busy = '1' then
                        -- Snoop Operand 1 (e.g., Data to Store for SW)
                        if lsq_table(i).opr1_valid = '0' then
                            if cdb1_valid = '1' and lsq_table(i).opr1_tag = cdb1_tag then
                                lsq_table(i).opr1 <= cdb1_value; lsq_table(i).opr1_valid <= '1';
                            elsif cdb2_valid = '1' and lsq_table(i).opr1_tag = cdb2_tag then
                                lsq_table(i).opr1 <= cdb2_value; lsq_table(i).opr1_valid <= '1';
                            elsif cdb3_valid = '1' and lsq_table(i).opr1_tag = cdb3_tag then
                                lsq_table(i).opr1 <= cdb3_value; lsq_table(i).opr1_valid <= '1';
                            elsif cdb4_valid = '1' and lsq_table(i).opr1_tag = cdb4_tag then
                                lsq_table(i).opr1 <= cdb4_value; lsq_table(i).opr1_valid <= '1';
                            end if;
                        end if;

                        -- Snoop Operand 2 (e.g., Base Address for LW/SW)
                        if lsq_table(i).opr2_valid = '0' then
                            if cdb1_valid = '1' and lsq_table(i).opr2_tag = cdb1_tag then
                                lsq_table(i).opr2 <= cdb1_value; lsq_table(i).opr2_valid <= '1';
                            elsif cdb2_valid = '1' and lsq_table(i).opr2_tag = cdb2_tag then
                                lsq_table(i).opr2 <= cdb2_value; lsq_table(i).opr2_valid <= '1';
                            elsif cdb3_valid = '1' and lsq_table(i).opr2_tag = cdb3_tag then
                                lsq_table(i).opr2 <= cdb3_value; lsq_table(i).opr2_valid <= '1';
                            elsif cdb4_valid = '1' and lsq_table(i).opr2_tag = cdb4_tag then
                                lsq_table(i).opr2 <= cdb4_value; lsq_table(i).opr2_valid <= '1';
                            end if;
                        end if;
                        
                        -- (Flag snooping omitted for brevity, add if LM/SM depend on flags)
                    end if;
                end loop;

                -------------------------------------------------
                -- 2. POINTER AND DATA MANAGEMENT
                -------------------------------------------------
                next_tail := tail_ptr;
                
                -- Handle Dispatches (Write to Tail)
                if dispatch_we_1 = '1' and is_full = '0' then
                    lsq_table(to_integer(next_tail)) <= dispatch_in_1;
                    next_tail := next_tail + 1;
                end if;
                
                if dispatch_we_2 = '1' and is_full = '0' then
                    lsq_table(to_integer(next_tail)) <= dispatch_in_2;
                    next_tail := next_tail + 1;
                end if;
                
                -- Update tail pointer
                tail_ptr <= next_tail;

                -- Handle Pop (Read from Head)
                if pop_head = '1' and is_empty = '0' then
                    lsq_table(to_integer(head_ptr)).busy <= '0';
                    head_ptr <= head_ptr + 1;
                end if;

                -- Update Count
                -- Calculate net change based on dispatch vs pop
                if pop_head = '1' and is_empty = '0' then
                    if (dispatch_we_1 = '1') and (dispatch_we_2 = '1') then
                        count <= count + 1; -- 2 in, 1 out
                    elsif (dispatch_we_1 = '1') xor (dispatch_we_2 = '1') then
                        count <= count;     -- 1 in, 1 out (no change)
                    else
                        count <= count - 1; -- 0 in, 1 out
                    end if;
                else
                    if (dispatch_we_1 = '1') and (dispatch_we_2 = '1') then
                        count <= count + 2; -- 2 in, 0 out
                    elsif (dispatch_we_1 = '1') xor (dispatch_we_2 = '1') then
                        count <= count + 1; -- 1 in, 0 out
                    end if;
                end if;

            end if;
        end if;
    end process;

end architecture rtl;

