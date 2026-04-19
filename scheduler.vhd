library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rs_types.all;

entity scheduler is
   port (
       ready_bits       : in  std_logic_vector(31 downto 0);
       read_addr_1      : out std_logic_vector(4 downto 0);
       read_addr_2      : out std_logic_vector(4 downto 0);
       read_addr_3      : out std_logic_vector(4 downto 0);

       read_row_1       : in  rs_entry_t;
       read_row_2       : in  rs_entry_t;
       read_row_3       : in  rs_entry_t;

       v1_input         : out std_logic;
       v2_input         : out std_logic;
       v3_input         : out std_logic;
		 
		 --  ALU-main slot 1
       alu_main_1_valid    : out std_logic;
       alu_main_1_opcode   : out std_logic_vector(3 downto 0);
       alu_main_1_comp_bit : out std_logic;
       alu_main_1_cond     : out std_logic_vector(1 downto 0);
       alu_main_1_opr1     : out std_logic_vector(15 downto 0);
       alu_main_1_opr2     : out std_logic_vector(15 downto 0);
       alu_main_1_imm9     : out std_logic_vector(8 downto 0);
       alu_main_1_carry    : out std_logic;
       alu_main_1_zero     : out std_logic;
       alu_main_1_dest_tag : out std_logic_vector(4 downto 0);
       alu_main_1_dest_tag_z : out std_logic_vector(4 downto 0);
       alu_main_1_dest_tag_c : out std_logic_vector(4 downto 0);

       --  ALU-main slot 2 
       alu_main_2_valid    : out std_logic;
       alu_main_2_opcode   : out std_logic_vector(3 downto 0);
       alu_main_2_comp_bit : out std_logic;
       alu_main_2_cond     : out std_logic_vector(1 downto 0);
       alu_main_2_opr1     : out std_logic_vector(15 downto 0);
       alu_main_2_opr2     : out std_logic_vector(15 downto 0);
       alu_main_2_imm9     : out std_logic_vector(8 downto 0);
       alu_main_2_carry    : out std_logic;
       alu_main_2_zero     : out std_logic;
       alu_main_2_dest_tag : out std_logic_vector(4 downto 0);
       alu_main_2_dest_tag_z : out std_logic_vector(4 downto 0);
       alu_main_2_dest_tag_c : out std_logic_vector(4 downto 0);

       -- ALU-branch 
       alu_branch_valid    : out std_logic;
       alu_branch_opcode   : out std_logic_vector(3 downto 0);
       alu_branch_pc       : out std_logic_vector(15 downto 0);
       alu_branch_opr1     : out std_logic_vector(15 downto 0);
       alu_branch_opr2     : out std_logic_vector(15 downto 0);
       alu_branch_imm9     : out std_logic_vector(8 downto 0);
       alu_branch_dest_tag : out std_logic_vector(2 downto 0);

       -- To ROB 
       alu_main_1_rob_idx     : out std_logic_vector(4 downto 0);
       alu_main_1_executing   : out std_logic;

       alu_main_2_rob_idx     : out std_logic_vector(4 downto 0);
       alu_main_2_executing   : out std_logic;

       alu_branch_rob_idx     : out std_logic_vector(4 downto 0);
       alu_branch_executing   : out std_logic
       );
end entity;

architecture rtl of scheduler is

    procedure drive_alu_main (
        signal valid    : out std_logic;
        signal opcode   : out std_logic_vector(3 downto 0);
        signal comp_bit : out std_logic;
        signal cond     : out std_logic_vector(1 downto 0);
        signal opr1     : out std_logic_vector(15 downto 0);
        signal opr2     : out std_logic_vector(15 downto 0);
        signal imm9     : out std_logic_vector(8 downto 0);
        signal carry    : out std_logic;
        signal zero     : out std_logic;
        signal dest_tag : out std_logic_vector(4 downto 0);
        signal dest_z   : out std_logic_vector(4 downto 0);
        signal dest_c   : out std_logic_vector(4 downto 0);
        entry           : in  rs_entry_t;
        en              : in  std_logic
    ) is -- REMOVED semicolon before "is"
    begin
        if en ='1' then
            valid    <= '1';
            opcode   <= entry.opcode(6 downto 3);
            comp_bit <= entry.opcode(2);
            cond     <= entry.opcode(1 downto 0);
            opr1     <= entry.opr1;
            opr2     <= entry.opr2;
            imm9     <= entry.imm9_opr;
            carry    <= entry.carry_value;
            zero     <= entry.zero_value;
            dest_tag <= entry.dest_tag;
            dest_z   <= entry.zero_dest_tag;
            dest_c   <= entry.carry_dest_tag;
        else
            valid    <= '0';
            opcode   <= (others => '0');
            comp_bit <= '0';
            cond     <= (others => '0');
            opr1     <= (others => '0');
            opr2     <= (others => '0');
            imm9     <= (others => '0');
            carry    <= '0';
            zero     <= '0';
            dest_tag <= (others => '0');
            dest_z   <= (others => '0');
            dest_c   <= (others => '0');
        end if;
    end procedure;

begin

    sched_comb : process(ready_bits, read_row_1, read_row_2, read_row_3)
        variable cand_idx   : integer_vector(0 to 2) := (others => 0);
        variable cand_count : integer range 0 to 3 := 0;
        variable main_slot  : integer range 0 to 2 := 0; -- Increased range to include 2
        variable branch_done: boolean := false;
        variable issued     : std_logic_vector(0 to 2) := (others => '0');
        variable row        : rs_entry_t;
    begin

        cand_count := 0;
        cand_idx   := (others => 0);

        for i in 0 to 31 loop
            exit when cand_count = 3;
            if ready_bits(i) = '1' then
                cand_idx(cand_count) := i;
                cand_count := cand_count + 1;
            end if;
        end loop;

        read_addr_1 <= std_logic_vector(to_unsigned(cand_idx(0), 5));
        read_addr_2 <= std_logic_vector(to_unsigned(cand_idx(1), 5));
        read_addr_3 <= std_logic_vector(to_unsigned(cand_idx(2), 5));

        main_slot   := 0;
        branch_done := false;
        issued      := (others => '0');

        for c in 0 to 2 loop
            if c < cand_count then -- Cleaner than "next when" for some compilers
                case c is
                    when 0 => row := read_row_1;
                    when 1 => row := read_row_2;
                    when 2 => row := read_row_3;
                    when others => row := read_row_1;
                end case;

                -- ALU main : opcode[6:5] = "00"
                if row.opcode(6 downto 5) = "00" then
                    if main_slot < 2 then
                        issued(c) := '1';
                        main_slot := main_slot + 1;
                    end if;
                -- ALU branch : opcode[6:5] = "10" or "11"
                elsif row.opcode(6 downto 5) = "10" or row.opcode(6 downto 5) = "11" then
                    if not branch_done then
                        issued(c)   := '1';
                        branch_done := true;
                    end if;
                end if;
            end if;
        end loop;

        v1_input <= issued(0);
        v2_input <= issued(1);
        v3_input <= issued(2);

        -- RESET OUTPUTS
        main_slot   := 0;
        branch_done := false;

        -- Default assignments to prevent latches
        alu_main_1_valid <= '0';
        alu_main_2_valid <= '0';
        alu_branch_valid <= '0';

        for c in 0 to 2 loop
            if issued(c) = '1' then
                case c is
                    when 0 => row := read_row_1;
                    when 1 => row := read_row_2;
                    when 2 => row := read_row_3;
                    when others => row := read_row_1;
                end case;

                if row.opcode(6 downto 5) = "00" then
                    if main_slot = 0 then
                        drive_alu_main(alu_main_1_valid, alu_main_1_opcode, alu_main_1_comp_bit, 
                                       alu_main_1_cond, alu_main_1_opr1, alu_main_1_opr2, 
                                       alu_main_1_imm9, alu_main_1_carry, alu_main_1_zero, 
                                       alu_main_1_dest_tag, alu_main_1_dest_tag_z, alu_main_1_dest_tag_c, 
                                       row, '1');
                        main_slot := 1;
                    else
                        drive_alu_main(alu_main_2_valid, alu_main_2_opcode, alu_main_2_comp_bit, 
                                       alu_main_2_cond, alu_main_2_opr1, alu_main_2_opr2, 
                                       alu_main_2_imm9, alu_main_2_carry, alu_main_2_zero, 
                                       alu_main_2_dest_tag, alu_main_2_dest_tag_z, alu_main_2_dest_tag_c, 
                                       row, '1');
                        main_slot := 2;
                    end if;
                else
                    alu_branch_valid    <= '1';
                    alu_branch_opcode   <= row.opcode(6 downto 3);
                    alu_branch_pc       <= row.PC;
                    alu_branch_opr1     <= row.opr1;
                    alu_branch_opr2     <= row.opr2;
                    alu_branch_imm9     <= row.imm9_opr;
                    alu_branch_dest_tag <= row.dest_tag(2 downto 0);
                    branch_done         := true;
                end if;
            end if;
        end loop;
        
        -- To ROB (Note: Ensure these signals are also driven to avoid latches)
        alu_main_1_executing <= issued(0); -- Example assignments
        alu_main_2_executing <= issued(1);
        alu_branch_executing <= issued(2);

    end process sched_comb;

end architecture rtl;
--
--architecture rtl of scheduler is
--
--
--   procedure drive_alu_main (
--       signal valid    : out std_logic;
--       signal opcode   : out std_logic_vector(3 downto 0);
--       signal comp_bit : out std_logic;
--       signal cond     : out std_logic_vector(1 downto 0);
--       signal opr1     : out std_logic_vector(15 downto 0);
--       signal opr2     : out std_logic_vector(15 downto 0);
--       signal imm9     : out std_logic_vector(8 downto 0);
--       signal carry    : out std_logic;
--       signal zero     : out std_logic;
--       signal dest_tag : out std_logic_vector(4 downto 0);
--       signal dest_z   : out std_logic_vector(4 downto 0);
--       signal dest_c   : out std_logic_vector(4 downto 0);
--       entry           : in  rs_entry_t;
--       en              : in  std_logic
--   ); is
--   begin
--       if en ='1' then
--           valid    <= '1';
--           opcode   <= entry.opcode(6 downto 3);
--           comp_bit <= entry.opcode(2);
--           cond     <= entry.opcode(1 downto 0);
--           opr1     <= entry.opr1;
--           opr2     <= entry.opr2;
--           imm9     <= entry.imm9_opr;
--           carry    <= entry.carry_value;
--           zero     <= entry.zero_value;
--           dest_tag <= entry.dest_tag;
--           dest_z   <= entry.zero_dest_tag;
--           dest_c   <= entry.carry_dest_tag;
--       else
--           valid    <= '0';
--           opcode   <= (others => '0');
--           comp_bit <= '0';
--           cond     <= (others => '0');
--           opr1     <= (others => '0');
--           opr2     <= (others => '0');
--           imm9     <= (others => '0');
--           carry    <= '0';
--           zero     <= '0';
--           dest_tag <= (others => '0');
--           dest_z   <= (others => '0');
--           dest_c   <= (others => '0');
--       end if;
--   end procedure;
--
--
--begin
--
--
--   sched_comb : process(ready_bits, read_row_1, read_row_2, read_row_3)
--
--
--       variable cand_idx   : integer_vector(0 to 2) := (others => 0);
--       variable cand_count : integer range 0 to 3 := 0;
--
--       variable main_slot  : integer range 0 to 1 := 0; -- counts 0,1
--       variable branch_done: boolean := false;
--
--       variable issued     : std_logic_vector(0 to 2) := (others => '0');
--       variable row        : rs_entry_t;
--
--
--   begin
--
--       cand_count := 0;
--       cand_idx   := (others => 0);
--
--
--       for i in 0 to 31 loop
--           exit when cand_count = 3;
--           if ready_bits(i) = '1' then
--               cand_idx(cand_count) := i;
--               cand_count := cand_count + 1;
--           end if;
--       end loop;
--
--       read_addr_1 <= std_logic_vector(to_unsigned(cand_idx(0), 5));
--       read_addr_2 <= std_logic_vector(to_unsigned(cand_idx(1), 5));
--       read_addr_3 <= std_logic_vector(to_unsigned(cand_idx(2), 5));
--
--       main_slot   := 0;
--       branch_done := false;
--       issued      := (others => '0');
--
--
--       for c in 0 to 2 loop
--           next when c >= cand_count;   -- skip unused slots
--
--           case c is
--               when 0 => row := read_row_1;
--               when 1 => row := read_row_2;
--               when 2 => row := read_row_3;
--               when others => row := read_row_1;
--           end case;
--
--
--           -- ALU main  :  opcode[6:5] = "00"
--           if row.opcode(6 downto 5) = "00" then
--               if main_slot < 2 then
--                   issued(c) := '1';
--                   main_slot := main_slot + 1;
--               end if;
--
--
--           -- ALU branch : opcode[6:5] = "10" or "11"
--           elsif row.opcode(6 downto 5) = "10" or
--                 row.opcode(6 downto 5) = "11" then
--               if not branch_done then
--                   issued(c)   := '1';
--                   branch_done := true;
--               end if;
--           end if;
--       end loop;
--
--
--       -- ---- STEP 3 : drive vX / clear signals ---------------
--       v1_input <= issued(0);
--       v2_input <= issued(1);
--       v3_input <= issued(2);
--
--
--       -- ---- STEP 4 : fill ALU output ports ------------------
--       --  Re-scan issued candidates and assign to ALU slots
--       main_slot   := 0;
--       branch_done := false;
--
--
--       -- Default all outputs off
--       alu_main_1_valid    <= '0';
--       alu_main_1_opcode   <= (others => '0');
--       alu_main_1_comp_bit <= '0';
--       alu_main_1_cond     <= (others => '0');
--       alu_main_1_opr1     <= (others => '0');
--       alu_main_1_opr2     <= (others => '0');
--       alu_main_1_imm9     <= (others => '0');
--       alu_main_1_carry    <= '0';
--       alu_main_1_zero     <= '0';
--       alu_main_1_dest_tag <= (others => '0');
--       alu_main_1_dest_tag_z <= (others => '0');
--       alu_main_1_dest_tag_c <= (others => '0');
--
--
--       alu_main_2_valid    <= '0';
--       alu_main_2_opcode   <= (others => '0');
--       alu_main_2_comp_bit <= '0';
--       alu_main_2_cond     <= (others => '0');
--       alu_main_2_opr1     <= (others => '0');
--       alu_main_2_opr2     <= (others => '0');
--       alu_main_2_imm9     <= (others => '0');
--       alu_main_2_carry    <= '0';
--       alu_main_2_zero     <= '0';
--       alu_main_2_dest_tag <= (others => '0');
--       alu_main_2_dest_tag_z <= (others => '0');
--       alu_main_2_dest_tag_c <= (others => '0');
--
--
--       alu_branch_valid    <= '0';
--       alu_branch_opcode   <= (others => '0');
--       alu_branch_pc       <= (others => '0');
--       alu_branch_opr1     <= (others => '0');
--       alu_branch_opr2     <= (others => '0');
--       alu_branch_imm9     <= (others => '0');
--       alu_branch_dest_tag <= (others => '0');
--
--
--       for c in 0 to 2 loop
--           next when issued(c) = '0';
--
--
--           case c is
--               when 0 => row := read_row_1;
--               when 1 => row := read_row_2;
--               when 2 => row := read_row_3;
--               when others => row := read_row_1;
--           end case;
--
--
--           if row.opcode(6 downto 5) = "00" then
--               -- ALU main
--               if main_slot = 0 then
--                   alu_main_1_valid      <= '1';
--                   alu_main_1_opcode     <= row.opcode(6 downto 3);
--                   alu_main_1_comp_bit   <= row.opcode(2);
--                   alu_main_1_cond       <= row.opcode(1 downto 0);
--                   alu_main_1_opr1       <= row.opr1;
--                   alu_main_1_opr2       <= row.opr2;
--                   alu_main_1_imm9       <= row.imm9_opr;
--                   alu_main_1_carry      <= row.carry_value;
--                   alu_main_1_zero       <= row.zero_value;
--                   alu_main_1_dest_tag   <= row.dest_tag;
--                   alu_main_1_dest_tag_z <= row.zero_dest_tag;
--                   alu_main_1_dest_tag_c <= row.carry_dest_tag;
--                   main_slot := 1;
--               else
--                   alu_main_2_valid      <= '1';
--                   alu_main_2_opcode     <= row.opcode(6 downto 3);
--                   alu_main_2_comp_bit   <= row.opcode(2);
--                   alu_main_2_cond       <= row.opcode(1 downto 0);
--                   alu_main_2_opr1       <= row.opr1;
--                   alu_main_2_opr2       <= row.opr2;
--                   alu_main_2_imm9       <= row.imm9_opr;
--                   alu_main_2_carry      <= row.carry_value;
--                   alu_main_2_zero       <= row.zero_value;
--                   alu_main_2_dest_tag   <= row.dest_tag;
--                   alu_main_2_dest_tag_z <= row.zero_dest_tag;
--                   alu_main_2_dest_tag_c <= row.carry_dest_tag;
--                   main_slot := 2;
--               end if;
--
--
--           else
--               -- ALU branch
--               alu_branch_valid    <= '1';
--               alu_branch_opcode   <= row.opcode(6 downto 3);
--               alu_branch_pc       <= row.PC;
--               alu_branch_opr1     <= row.opr1;
--               alu_branch_opr2     <= row.opr2;
--               alu_branch_imm9     <= row.imm9_opr;
--               alu_branch_dest_tag <= row.dest_tag(2 downto 0);
--               branch_done := true;
--           end if;
--
--
--       end loop;
--
--
--   end process sched_comb;
--
--
--end architecture rtl;

