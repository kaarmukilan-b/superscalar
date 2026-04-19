library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rs_types.all;

entity Decode_Rename is
    port (
        clk, reset : in std_logic;
        
        -- From Instruction Buffer
        in_Instr1, in_PC1, in_PCnext_predicted1 : in std_logic_vector(15 downto 0);
        in_valid1 : in std_logic;
        in_Instr2, in_PC2, in_PCnext_predicted2 : in std_logic_vector(15 downto 0);
        in_valid2 : in std_logic;
        
        -- NEW: Structural Hazard Flags (Inputs)
        rs_full       : in std_logic;
        lsq_full      : in std_logic;
        rrf_full      : in std_logic;
        frrf_c_full   : in std_logic;
        frrf_z_full   : in std_logic;
        
        -- NEW: Stall Output
        decode_stall  : out std_logic;
        
        -- To Reservation Station
        rs_dispatch_we_1, rs_dispatch_we_2   : out std_logic;
        rs_dispatch_in_1, rs_dispatch_in_2   : out rs_entry_t;
        
        -- To Load/Store Queue (LSQ)
        lsq_dispatch_we_1, lsq_dispatch_we_2 : out std_logic;
        lsq_dispatch_in_1, lsq_dispatch_in_2 : out rs_entry_t;
        
        -- ARF Interfaces (4 Read Ports, 2 Write Ports)
        arf_read_addr_1, arf_read_addr_2, arf_read_addr_3, arf_read_addr_4 : out std_logic_vector(2 downto 0);
        arf_read_data_1, arf_read_data_2, arf_read_data_3, arf_read_data_4 : in  std_logic_vector(15 downto 0);
        arf_read_busy_1, arf_read_busy_2, arf_read_busy_3, arf_read_busy_4 : in  std_logic;
        arf_read_tag_1,  arf_read_tag_2,  arf_read_tag_3,  arf_read_tag_4  : in  std_logic_vector(4 downto 0);
        arf_write_en_1,  arf_write_en_2 : out std_logic;
        arf_write_addr_1,arf_write_addr_2 : out std_logic_vector(2 downto 0);
        arf_write_tag_1, arf_write_tag_2  : out std_logic_vector(4 downto 0);
        
        -- RRF Interfaces (4 Read Ports, Free Tags, Fill Commands)
        rrf_read_tag_1, rrf_read_tag_2, rrf_read_tag_3, rrf_read_tag_4 : out std_logic_vector(4 downto 0);
        rrf_read_val_1, rrf_read_val_2, rrf_read_val_3, rrf_read_val_4 : in  std_logic_vector(15 downto 0);
        rrf_read_valid_1, rrf_read_valid_2, rrf_read_valid_3, rrf_read_valid_4 : in std_logic;
        rrf_free_tag_1, rrf_free_tag_2 : in std_logic_vector(4 downto 0);
        rrf_fill_1, rrf_fill_2 : out std_logic;
        
        -- CCF Interfaces
        ccf_c_data, ccf_c_busy : in std_logic;
        ccf_c_tag : in std_logic_vector(4 downto 0);
        ccf_z_data, ccf_z_busy : in std_logic;
        ccf_z_tag : in std_logic_vector(4 downto 0);
        ccf_c_we_1, ccf_c_we_2, ccf_z_we_1, ccf_z_we_2 : out std_logic;
        ccf_c_tag_in_1, ccf_c_tag_in_2, ccf_z_tag_in_1, ccf_z_tag_in_2 : out std_logic_vector(4 downto 0);
        
        -- FRRF Interfaces
        frrf_c_read_tag_1, frrf_c_read_tag_2 : out std_logic_vector(4 downto 0);
        frrf_c_read_val_1, frrf_c_read_val_2 : in std_logic;
        frrf_c_read_valid_1, frrf_c_read_valid_2 : in std_logic;
        frrf_c_free_tag_1, frrf_c_free_tag_2 : in std_logic_vector(4 downto 0);
        frrf_c_fill_1, frrf_c_fill_2 : out std_logic;
        
        frrf_z_read_tag_1, frrf_z_read_tag_2 : out std_logic_vector(4 downto 0);
        frrf_z_read_val_1, frrf_z_read_val_2 : in std_logic;
        frrf_z_read_valid_1, frrf_z_read_valid_2 : in std_logic;
        frrf_z_free_tag_1, frrf_z_free_tag_2 : in std_logic_vector(4 downto 0);
        frrf_z_fill_1, frrf_z_fill_2 : out std_logic
    );
end entity Decode_Rename;

architecture rtl of Decode_Rename is

    type decode_info_t is record
        opcode   : std_logic_vector(3 downto 0);
        rs1, rs2 : std_logic_vector(2 downto 0);
        rd       : std_logic_vector(2 downto 0);
        use_rs1, use_rs2, use_c, use_z : std_logic;
        write_rd, write_c, write_z : std_logic;
        imm9     : std_logic_vector(8 downto 0);
        is_mem   : std_logic;
    end record;

    signal d1, d2 : decode_info_t;
    signal rs_out_1, rs_out_2 : rs_entry_t;

begin

    -- 1. Instruction Decoding & Relevance Identification
    process(in_Instr1, in_Instr2)
    begin
        -- Defaults for I1
        d1 <= (opcode => in_Instr1(15 downto 12), rs1 => "000", rs2 => "000", rd => "000",
               use_rs1 => '0', use_rs2 => '0', use_c => '0', use_z => '0',
               write_rd => '0', write_c => '0', write_z => '0', 
               imm9 => (others => '0'), is_mem => '0');
               
        case in_Instr1(15 downto 12) is
            when "0001" => -- R-Type (ADA, ADC, etc.)
                d1.rs1 <= in_Instr1(11 downto 9); d1.rs2 <= in_Instr1(8 downto 6); d1.rd <= in_Instr1(5 downto 3);
                d1.use_rs1 <= '1'; d1.use_rs2 <= '1'; d1.write_rd <= '1'; d1.write_c <= '1'; d1.write_z <= '1';
                if in_Instr1(1 downto 0) = "10" then d1.use_c <= '1'; end if; -- ADC
                if in_Instr1(1 downto 0) = "01" then d1.use_z <= '1'; end if; -- ADZ
                    
            when "0010" => -- R-Type (NAND type etc.)
                d1.rs1 <= in_Instr1(11 downto 9); d1.rs2 <= in_Instr1(8 downto 6); d1.rd <= in_Instr1(5 downto 3);
                d1.use_rs1 <= '1'; d1.use_rs2 <= '1'; d1.write_rd <= '1'; d1.write_c <= '1'; d1.write_z <= '1';
                if in_Instr1(1 downto 0) = "10" then d1.use_c <= '1'; end if; -- C
                if in_Instr1(1 downto 0) = "01" then d1.use_z <= '1'; end if; -- Z
            
            when "0000" => -- I-Type (ADI)
                d1.rs1 <= in_Instr1(11 downto 9); d1.rd <= in_Instr1(8 downto 6);
                d1.imm9 <= std_logic_vector(resize(signed(in_Instr1(5 downto 0)), 9));
                d1.use_rs1 <= '1'; d1.write_rd <= '1'; d1.write_c <= '1'; d1.write_z <= '1';
                    
            when "0011" => -- J-Type (LLI)
                d1.rd <= in_Instr1(11 downto 9);
                d1.imm9 <= std_logic_vector(resize(unsigned(in_Instr1(8 downto 0)), 9));
                d1.write_rd <= '1';
                    
            when "0100" => -- I-Type (LW)
                d1.rs1 <= in_Instr1(8 downto 6); d1.rd <= in_Instr1(11 downto 9);
                d1.imm9 <= std_logic_vector(resize(signed(in_Instr1(5 downto 0)), 9));
                d1.use_rs1 <= '1'; d1.write_rd <= '1'; d1.write_z <= '1';
                d1.is_mem <= '1'; -- Route to LSQ
                    
            when "0101" => -- I-Type (SW)
                d1.rs1 <= in_Instr1(11 downto 9); d1.rs2 <= in_Instr1(8 downto 6);
                d1.use_rs1 <= '1'; d1.use_rs2 <= '1';
                d1.imm9 <= std_logic_vector(resize(signed(in_Instr1(5 downto 0)), 9));
                d1.is_mem <= '1'; -- Route to LSQ
                
            when "1000" | "1001" | "1010" => -- Branch (BEQ)
                d1.rs1 <= in_Instr1(11 downto 9); d1.rs2 <= in_Instr1(8 downto 6);
                d1.imm9 <= std_logic_vector(resize(signed(in_Instr1(5 downto 0)), 9));
                d1.use_rs1 <= '1'; d1.use_rs2 <= '1';
                
            when "1100" => -- J-Type (JAL)
                d1.rd <= in_Instr1(11 downto 9);
                d1.imm9 <= std_logic_vector(resize(unsigned(in_Instr1(8 downto 0)), 9));
                d1.write_rd <= '1';
                    
            when "1111" => -- J-Type (JRI)
                d1.rs1 <= in_Instr1(11 downto 9);
                d1.imm9 <= std_logic_vector(resize(unsigned(in_Instr1(8 downto 0)), 9));
                d1.use_rs1 <= '1';
                    
            when "1101" => -- I-Type (JLR)
                d1.rs2 <= in_Instr1(8 downto 6);
                d1.use_rs2 <= '1';
                d1.imm9 <= std_logic_vector(resize(signed(in_Instr1(5 downto 0)), 9));
                d1.write_rd <= '1';
                d1.rd <= in_Instr1(11 downto 9);
                
            when others => null; 
        end case;

        -- Defaults for I2
        d2 <= (opcode => in_Instr2(15 downto 12), rs1 => "000", rs2 => "000", rd => "000",
               use_rs1 => '0', use_rs2 => '0', use_c => '0', use_z => '0',
               write_rd => '0', write_c => '0', write_z => '0', 
               imm9 => (others => '0'), is_mem => '0');
               
        case in_Instr2(15 downto 12) is
            when "0001" => -- R-Type (ADA, ADC, etc.)
                d2.rs1 <= in_Instr2(11 downto 9); d2.rs2 <= in_Instr2(8 downto 6); d2.rd <= in_Instr2(5 downto 3);
                d2.use_rs1 <= '1'; d2.use_rs2 <= '1'; d2.write_rd <= '1'; d2.write_c <= '1'; d2.write_z <= '1';
                if in_Instr2(1 downto 0) = "10" then d2.use_c <= '1'; end if; -- ADC
                if in_Instr2(1 downto 0) = "01" then d2.use_z <= '1'; end if; -- ADZ
                    
            when "0010" => -- R-Type (NAND type etc.)
                d2.rs1 <= in_Instr2(11 downto 9); d2.rs2 <= in_Instr2(8 downto 6); d2.rd <= in_Instr2(5 downto 3);
                d2.use_rs1 <= '1'; d2.use_rs2 <= '1'; d2.write_rd <= '1'; d2.write_c <= '1'; d2.write_z <= '1';
                if in_Instr2(1 downto 0) = "10" then d2.use_c <= '1'; end if; -- C
                if in_Instr2(1 downto 0) = "01" then d2.use_z <= '1'; end if; -- Z
            
            when "0000" => -- I-Type (ADI)
                d2.rs1 <= in_Instr2(11 downto 9); d2.rd <= in_Instr2(8 downto 6);
                d2.imm9 <= std_logic_vector(resize(signed(in_Instr2(5 downto 0)), 9));
                d2.use_rs1 <= '1'; d2.write_rd <= '1'; d2.write_c <= '1'; d2.write_z <= '1';
                    
            when "0011" => -- J-Type (LLI)
                d2.rd <= in_Instr2(11 downto 9);
                d2.imm9 <= std_logic_vector(resize(unsigned(in_Instr2(8 downto 0)), 9));
                d2.write_rd <= '1';
                    
            when "0100" => -- I-Type (LW)
                d2.rs1 <= in_Instr2(8 downto 6); d2.rd <= in_Instr2(11 downto 9);
                d2.imm9 <= std_logic_vector(resize(signed(in_Instr2(5 downto 0)), 9));
                d2.use_rs1 <= '1'; d2.write_rd <= '1'; d2.write_z <= '1';
                d2.is_mem <= '1'; -- Route to LSQ
                    
            when "0101" => -- I-Type (SW)
                d2.rs1 <= in_Instr2(11 downto 9); d2.rs2 <= in_Instr2(8 downto 6);
                d2.use_rs1 <= '1'; d2.use_rs2 <= '1';
                d2.imm9 <= std_logic_vector(resize(signed(in_Instr2(5 downto 0)), 9));
                d2.is_mem <= '1'; -- Route to LSQ
                
            when "1000" | "1001" | "1010" => -- Branch (BEQ)
                d2.rs1 <= in_Instr2(11 downto 9); d2.rs2 <= in_Instr2(8 downto 6);
                d2.imm9 <= std_logic_vector(resize(signed(in_Instr2(5 downto 0)), 9));
                d2.use_rs1 <= '1'; d2.use_rs2 <= '1';
                
            when "1100" => -- J-Type (JAL)
                d2.rd <= in_Instr2(11 downto 9);
                d2.imm9 <= std_logic_vector(resize(unsigned(in_Instr2(8 downto 0)), 9));
                d2.write_rd <= '1';
                    
            when "1111" => -- J-Type (JRI)
                d2.rs1 <= in_Instr2(11 downto 9);
                d2.imm9 <= std_logic_vector(resize(unsigned(in_Instr2(8 downto 0)), 9));
                d2.use_rs1 <= '1';
                    
            when "1101" => -- I-Type (JLR)
                d2.rs2 <= in_Instr2(8 downto 6);
                d2.use_rs2 <= '1';
                d2.imm9 <= std_logic_vector(resize(signed(in_Instr2(5 downto 0)), 9));
                d2.write_rd <= '1';
                d2.rd <= in_Instr2(11 downto 9);
                
            when others => null; 
        end case;
    end process;

    -- Map ARF Read Ports
    arf_read_addr_1 <= d1.rs1; arf_read_addr_2 <= d1.rs2;
    arf_read_addr_3 <= d2.rs1; arf_read_addr_4 <= d2.rs2;

    -- Map RRF Read Ports to ARF Tags
    rrf_read_tag_1 <= arf_read_tag_1; rrf_read_tag_2 <= arf_read_tag_2;
    rrf_read_tag_3 <= arf_read_tag_3; rrf_read_tag_4 <= arf_read_tag_4;
    frrf_c_read_tag_1 <= ccf_c_tag;   frrf_c_read_tag_2 <= ccf_c_tag;
    frrf_z_read_tag_1 <= ccf_z_tag;   frrf_z_read_tag_2 <= ccf_z_tag;

    -- 2. Rename & RS Assembly Logic
    process(all)
        variable stall_req : std_logic;
    begin
        -- Default RS states (Clear all bits)
        rs_out_1 <= (busy => '1', PC => in_PC1, opcode => "000" & d1.opcode,
                     opr1 => (others => '0'), opr1_valid => '0', opr1_tag => (others => '0'),
                     opr2 => (others => '0'), opr2_valid => '0', opr2_tag => (others => '0'),
                     imm9_opr => (others => '0'), imm9_valid => '0', dest_tag => (others => '0'),
                     ROB_index => (others => '0'), carry_value => '0', carry_tag => (others => '0'),
                     carry_valid => '0', carry_dest_tag => (others => '0'),
                     zero_value => '0', zero_tag => (others => '0'), zero_valid => '0',
                     zero_dest_tag => (others => '0'), PCnext_pred => (others => '0'),
                     PC_next_valid => '0', ready => '0');
        rs_out_2 <= (busy => '1', PC => in_PC2, opcode => "000" & d2.opcode,
                     opr1 => (others => '0'), opr1_valid => '0', opr1_tag => (others => '0'),
                     opr2 => (others => '0'), opr2_valid => '0', opr2_tag => (others => '0'),
                     imm9_opr => (others => '0'), imm9_valid => '0', dest_tag => (others => '0'),
                     ROB_index => (others => '0'), carry_value => '0', carry_tag => (others => '0'),
                     carry_valid => '0', carry_dest_tag => (others => '0'),
                     zero_value => '0', zero_tag => (others => '0'), zero_valid => '0',
                     zero_dest_tag => (others => '0'), PCnext_pred => (others => '0'),
                     PC_next_valid => '0', ready => '0');

        --------------------------------------------------------
        -- INSTRUCTION 1: RENAME
        --------------------------------------------------------
        -- Operand 1
        if d1.use_rs1 = '0' then 
            rs_out_1.opr1_valid <= '1'; -- Irrelevant field, set valid to not block RS
        else
            if arf_read_busy_1 = '0' then
                rs_out_1.opr1 <= arf_read_data_1; rs_out_1.opr1_valid <= '1';
            elsif rrf_read_valid_1 = '1' then
                rs_out_1.opr1 <= rrf_read_val_1; rs_out_1.opr1_valid <= '1';
            else
                rs_out_1.opr1_tag <= arf_read_tag_1; rs_out_1.opr1_valid <= '0';
            end if;
        end if;

        -- Carry Source
        if d1.use_c = '0' then 
            rs_out_1.carry_valid <= '1'; 
        else
            if ccf_c_busy = '0' then
                rs_out_1.carry_value <= ccf_c_data; rs_out_1.carry_valid <= '1';
            elsif frrf_c_read_valid_1 = '1' then
                rs_out_1.carry_value <= frrf_c_read_val_1; rs_out_1.carry_valid <= '1';
            else
                rs_out_1.carry_tag <= ccf_c_tag; rs_out_1.carry_valid <= '0';
            end if;
        end if;
        
        -- Operand 2 (I1)
        if d1.use_rs2 = '0' then 
            rs_out_1.opr2_valid <= '1'; 
        else
            if arf_read_busy_2 = '0' then
                rs_out_1.opr2 <= arf_read_data_2; rs_out_1.opr2_valid <= '1';
            elsif rrf_read_valid_2 = '1' then
                rs_out_1.opr2 <= rrf_read_val_2; rs_out_1.opr2_valid <= '1';
            else
                rs_out_1.opr2_tag <= arf_read_tag_2; rs_out_1.opr2_valid <= '0';
            end if;
        end if;

        -- Zero Source (I1)
        if d1.use_z = '0' then 
            rs_out_1.zero_valid <= '1'; 
        else
            if ccf_z_busy = '0' then
                rs_out_1.zero_value <= ccf_z_data; rs_out_1.zero_valid <= '1';
            elsif frrf_z_read_valid_1 = '1' then
                rs_out_1.zero_value <= frrf_z_read_val_1; rs_out_1.zero_valid <= '1';
            else
                rs_out_1.zero_tag <= ccf_z_tag; rs_out_1.zero_valid <= '0';
            end if;
        end if;

        --------------------------------------------------------
        -- INSTRUCTION 2: RENAME (With Intra-Cycle Dependency)
        --------------------------------------------------------
        -- Operand 1
        if d2.use_rs1 = '0' then 
            rs_out_2.opr1_valid <= '1'; 
        else
            -- Check Intra-Cycle RAW Hazard first
            if (d1.write_rd = '1') and (d1.rd = d2.rs1) then
                rs_out_2.opr1_tag <= rrf_free_tag_1; 
                rs_out_2.opr1_valid <= '0';
            -- Standard Check
            elsif arf_read_busy_3 = '0' then
                rs_out_2.opr1 <= arf_read_data_3; rs_out_2.opr1_valid <= '1';
            elsif rrf_read_valid_3 = '1' then
                rs_out_2.opr1 <= rrf_read_val_3; rs_out_2.opr1_valid <= '1';
            else
                rs_out_2.opr1_tag <= arf_read_tag_3; rs_out_2.opr1_valid <= '0';
            end if;
        end if;

        -- Carry Source (Intra-Cycle)
        if d2.use_c = '0' then 
            rs_out_2.carry_valid <= '1';
        else
            if d1.write_c = '1' then
                rs_out_2.carry_tag <= frrf_c_free_tag_1; rs_out_2.carry_valid <= '0';
            elsif ccf_c_busy = '0' then
                rs_out_2.carry_value <= ccf_c_data; rs_out_2.carry_valid <= '1';
            elsif frrf_c_read_valid_2 = '1' then
                rs_out_2.carry_value <= frrf_c_read_val_2; rs_out_2.carry_valid <= '1';
            else
                rs_out_2.carry_tag <= ccf_c_tag; rs_out_2.carry_valid <= '0';
            end if;
        end if;

        -- Operand 2 (I2)
        if d2.use_rs2 = '0' then 
            rs_out_2.opr2_valid <= '1'; 
        else
            -- Check Intra-Cycle RAW Hazard first
            if (d1.write_rd = '1') and (d1.rd = d2.rs2) then
                rs_out_2.opr2_tag <= rrf_free_tag_1; 
                rs_out_2.opr2_valid <= '0';
            -- Standard Check
            elsif arf_read_busy_4 = '0' then
                rs_out_2.opr2 <= arf_read_data_4; rs_out_2.opr2_valid <= '1';
            elsif rrf_read_valid_4 = '1' then
                rs_out_2.opr2 <= rrf_read_val_4; rs_out_2.opr2_valid <= '1';
            else
                rs_out_2.opr2_tag <= arf_read_tag_4; rs_out_2.opr2_valid <= '0';
            end if;
        end if;

        -- Zero Source (Intra-Cycle I2)
        if d2.use_z = '0' then 
            rs_out_2.zero_valid <= '1';
        else
            if d1.write_z = '1' then
                rs_out_2.zero_tag <= frrf_z_free_tag_1; rs_out_2.zero_valid <= '0';
            elsif ccf_z_busy = '0' then
                rs_out_2.zero_value <= ccf_z_data; rs_out_2.zero_valid <= '1';
            elsif frrf_z_read_valid_2 = '1' then
                rs_out_2.zero_value <= frrf_z_read_val_2; rs_out_2.zero_valid <= '1';
            else
                rs_out_2.zero_tag <= ccf_z_tag; rs_out_2.zero_valid <= '0';
            end if;
        end if;

        --------------------------------------------------------
        -- DESTINATION TAG ALLOCATION
        --------------------------------------------------------
        
        -- Defaults (prevents latches if valid is 0)
        arf_write_en_1 <= '0'; arf_write_en_2 <= '0';
        ccf_c_we_1 <= '0'; ccf_c_we_2 <= '0';
        ccf_z_we_1 <= '0'; ccf_z_we_2 <= '0';
        rrf_fill_1 <= '0'; rrf_fill_2 <= '0';
        frrf_c_fill_1 <= '0'; frrf_c_fill_2 <= '0';
        frrf_z_fill_1 <= '0'; frrf_z_fill_2 <= '0';

        if in_valid1 = '1' then
            if d1.write_rd = '1' then
                rs_out_1.dest_tag <= rrf_free_tag_1;
                arf_write_en_1 <= '1'; arf_write_addr_1 <= d1.rd; arf_write_tag_1 <= rrf_free_tag_1;
                rrf_fill_1 <= '1';
            end if;
            if d1.write_c = '1' then
                rs_out_1.carry_dest_tag <= frrf_c_free_tag_1;
                ccf_c_we_1 <= '1'; ccf_c_tag_in_1 <= frrf_c_free_tag_1;
                frrf_c_fill_1 <= '1';
            end if;
            if d1.write_z = '1' then
                rs_out_1.zero_dest_tag <= frrf_z_free_tag_1;
                ccf_z_we_1 <= '1'; ccf_z_tag_in_1 <= frrf_z_free_tag_1;
                frrf_z_fill_1 <= '1';
            end if;
        end if;

        if in_valid2 = '1' then
            if d2.write_rd = '1' then
                rs_out_2.dest_tag <= rrf_free_tag_2;
                arf_write_en_2 <= '1'; arf_write_addr_2 <= d2.rd; arf_write_tag_2 <= rrf_free_tag_2;
                rrf_fill_2 <= '1';
                
                -- Intra-cycle WAW (Write-After-Write) hazard check
                if (d1.write_rd = '1') and (d1.rd = d2.rd) then
                    arf_write_en_1 <= '0'; -- Let I2's tag override I1's tag in ARF
                end if;
            end if;

            if d2.write_c = '1' then
                rs_out_2.carry_dest_tag <= frrf_c_free_tag_2;
                ccf_c_we_2 <= '1'; ccf_c_tag_in_2 <= frrf_c_free_tag_2;
                frrf_c_fill_2 <= '1';
                
                if (d1.write_c = '1') then ccf_c_we_1 <= '0'; end if;
            end if;

            if d2.write_z = '1' then
                rs_out_2.zero_dest_tag <= frrf_z_free_tag_2;
                ccf_z_we_2 <= '1'; ccf_z_tag_in_2 <= frrf_z_free_tag_2;
                frrf_z_fill_2 <= '1';
                
                if (d1.write_z = '1') then ccf_z_we_1 <= '0'; end if;
            end if;
        end if;
        
        --------------------------------------------------------
        -- FINAL DISPATCH ROUTING (RS vs LSQ)
        --------------------------------------------------------
        
        -- Defaults
        rs_dispatch_we_1 <= '0'; lsq_dispatch_we_1 <= '0';
        rs_dispatch_we_2 <= '0'; lsq_dispatch_we_2 <= '0';
        rs_dispatch_in_1 <= rs_out_1; lsq_dispatch_in_1 <= rs_out_1;
        rs_dispatch_in_2 <= rs_out_2; lsq_dispatch_in_2 <= rs_out_2;

        if in_valid1 = '1' then
            if d1.is_mem = '1' then
                lsq_dispatch_we_1 <= '1';
            else
                rs_dispatch_we_1  <= '1';
            end if;
        end if;

        if in_valid2 = '1' then
            if d2.is_mem = '1' then
                lsq_dispatch_we_2 <= '1';
            else
                rs_dispatch_we_2  <= '1';
            end if;
        end if;

        --------------------------------------------------------
        -- STALL LOGIC OVERRIDE
        --------------------------------------------------------
        stall_req := '0';
        
        -- Check structural hazards for RS / LSQ destination queues
        if (in_valid1 = '1' and d1.is_mem = '0' and rs_full = '1') then stall_req := '1'; end if;
        if (in_valid2 = '1' and d2.is_mem = '0' and rs_full = '1') then stall_req := '1'; end if;
        if (in_valid1 = '1' and d1.is_mem = '1' and lsq_full = '1') then stall_req := '1'; end if;
        if (in_valid2 = '1' and d2.is_mem = '1' and lsq_full = '1') then stall_req := '1'; end if;
        
        -- Check Tag exhaustion dynamically
        if ((in_valid1 = '1' and d1.write_rd = '1') or (in_valid2 = '1' and d2.write_rd = '1')) and rrf_full = '1' then stall_req := '1'; end if;
        if ((in_valid1 = '1' and d1.write_c = '1') or (in_valid2 = '1' and d2.write_c = '1')) and frrf_c_full = '1' then stall_req := '1'; end if;
        if ((in_valid1 = '1' and d1.write_z = '1') or (in_valid2 = '1' and d2.write_z = '1')) and frrf_z_full = '1' then stall_req := '1'; end if;

        -- Apply Stall
        decode_stall <= stall_req;

        if stall_req = '1' then
            -- Nullify all write enables to completely freeze state
            arf_write_en_1 <= '0'; arf_write_en_2 <= '0';
            ccf_c_we_1 <= '0'; ccf_c_we_2 <= '0';
            ccf_z_we_1 <= '0'; ccf_z_we_2 <= '0';
            rrf_fill_1 <= '0'; rrf_fill_2 <= '0';
            frrf_c_fill_1 <= '0'; frrf_c_fill_2 <= '0';
            frrf_z_fill_1 <= '0'; frrf_z_fill_2 <= '0';
            rs_dispatch_we_1 <= '0'; rs_dispatch_we_2 <= '0';
            lsq_dispatch_we_1 <= '0'; lsq_dispatch_we_2 <= '0';
        end if;
        
    end process;
end architecture rtl;


