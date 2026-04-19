library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rs_types.all;
use work.rob_pkg.all;

entity datapath is
	port( clk, reset : in std_logic);
end entity;

architecture struct of datapath is 
	
	-- Constants
	constant DATA_BITS    : integer := 16;
	constant ARCH_REGS    : integer := 3;   -- 8 architectural registers (3 bits)
	constant TAG_BITS_RR  : integer := 5;   -- 32 rename registers (5 bits)
	constant ROB_IDX      : integer := 6;   -- 64-entry ROB (6 bits)
	
component mispredict_recovery is
    port (
        clk : in std_logic;
        rst : in std_logic;

           commit_valid_s0 : in std_logic;
        commit_entry_s0 : in rob_entry_t;

        commit_valid_s1 : in std_logic;
        commit_entry_s1 : in rob_entry_t;

        arf_committed    : in std_logic_vector(8*DATA_BITS-1 downto 0);

        rob_flush        : out std_logic;
        rs_flush         : out std_logic;

        arf_restore_en   : out std_logic;
        arf_restore_data : out std_logic_vector(8*DATA_BITS-1 downto 0);

        commit_mispredict : out std_logic;
        commit_correct_pc : out std_logic_vector(DATA_BITS-1 downto 0);

        commit_upd0_en     : out std_logic;
        commit_upd0_pc     : out std_logic_vector(DATA_BITS-1 downto 0);
        commit_upd0_taken  : out std_logic;
        commit_upd0_target : out std_logic_vector(DATA_BITS-1 downto 0);

        commit_upd1_en     : out std_logic;
        commit_upd1_pc     : out std_logic_vector(DATA_BITS-1 downto 0);
        commit_upd1_taken  : out std_logic;
        commit_upd1_target : out std_logic_vector(DATA_BITS-1 downto 0)
    );
end component;

component branch_predictor is
    generic (
        ADDR_WIDTH   : integer := 16;
        BTB_ENTRIES  : integer := 16;
        BTB_IDX_BITS : integer := 4;
        BTB_TAG_BITS : integer := 11
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        fetch_pc : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        commit_mispredict : in std_logic;
        commit_correct_pc : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        commit_upd0_en     : in std_logic;
        commit_upd0_pc     : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        commit_upd0_taken  : in std_logic;
        commit_upd0_target : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        commit_upd1_en     : in std_logic;
        commit_upd1_pc     : in std_logic_vector(ADDR_WIDTH-1 downto 0);
        commit_upd1_taken  : in std_logic;
        commit_upd1_target : in std_logic_vector(ADDR_WIDTH-1 downto 0);

        next_pc  : out std_logic_vector(ADDR_WIDTH-1 downto 0);

        valid_s0 : out std_logic;
        valid_s1 : out std_logic;

        flush    : out std_logic
    );
end component;

component Instr_Mem is -- byte addressing
    port (
        RA1, RA2 : in std_logic_vector(15 downto 0);
        RD1, RD2 : out std_logic_vector(15 downto 0)
    );
end component;
	
component RRF is -- a row contains busy bit, value, valid 
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
end component;

component RRF_flags is
 port (
	  clk, reset                          : in std_logic;
	  
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
end component;
	
component ALU_main is
    port (
        -- Inputs
        opcode           : in  std_logic_vector(3 downto 0);
        cond_bits        : in  std_logic_vector(1 downto 0); -- [cite: 26]
        comp_bit         : in  std_logic;                    -- [cite: 26]
        operand_1        : in  std_logic_vector(15 downto 0);
        operand_2        : in  std_logic_vector(15 downto 0);
        imm_9            : in  std_logic_vector(8 downto 0);
        c_flag_in        : in  std_logic;
        z_flag_in        : in  std_logic;
        
        -- Destination Tag Inputs (Wire passing)
        dest_tag_reg_in  : in  std_logic_vector(4 downto 0);
        dest_tag_z_in    : in  std_logic_vector(4 downto 0);
        dest_tag_c_in    : in  std_logic_vector(4 downto 0);
        
        -- Outputs
        result           : out std_logic_vector(15 downto 0);
        z_flag_out       : out std_logic;
        c_flag_out       : out std_logic;
        
        -- Tag/Valid Outputs
        dest_tag_reg_out : out std_logic_vector(4 downto 0);
        dest_tag_z_out   : out std_logic_vector(4 downto 0);
        dest_tag_c_out   : out std_logic_vector(4 downto 0);
        dest_reg_valid   : out std_logic;
        dest_z_valid     : out std_logic;
        dest_c_valid     : out std_logic
    );
end component;

component ALU_branch is
    port (
        -- Inputs
        opcode           : in  std_logic_vector(3 downto 0);
        pc_in            : in  std_logic_vector(15 downto 0);
        operand_1        : in  std_logic_vector(15 downto 0); -- Usually RA
        operand_2        : in  std_logic_vector(15 downto 0); -- Usually RB
        imm_9            : in  std_logic_vector(8 downto 0);
        
        -- Tag/Valid Inputs (Wire passing)
        dest_tag_reg_in  : in  std_logic_vector(2 downto 0);
        
        -- Outputs
        take_branch      : out std_logic; -- 1 if Jump or Branch Condition met
        target_address   : out std_logic_vector(15 downto 0);
        
        -- Register Writeback (for Link operations)
        dest_tag_reg_out : out std_logic_vector(2 downto 0);
        dest_reg_valid   : out std_logic;
        dest_reg_value   : out std_logic_vector(15 downto 0)
    );
end component;

component adder_2 is
    port (input_16  : in  std_logic_vector(15 downto 0); output_16 : out std_logic_vector(15 downto 0) );
end component;

component CCF is
    generic (
        TAG_WIDTH : integer := 5
    );
    port (
        clk          : in  std_logic;
        reset        : in  std_logic;

        C_data_out   : out std_logic;
        C_busy_out   : out std_logic;
        C_tag_out    : out std_logic_vector(TAG_WIDTH-1 downto 0);

        Z_data_out   : out std_logic;
        Z_busy_out   : out std_logic;
        Z_tag_out    : out std_logic_vector(TAG_WIDTH-1 downto 0);

        C_write_en_1 : in  std_logic;
        C_data_in_1  : in  std_logic;
        C_busy_in_1  : in  std_logic;
        C_tag_in_1   : in  std_logic_vector(TAG_WIDTH-1 downto 0);

        Z_write_en_1 : in  std_logic;
        Z_data_in_1  : in  std_logic;
        Z_busy_in_1  : in  std_logic;
        Z_tag_in_1   : in  std_logic_vector(TAG_WIDTH-1 downto 0);

        C_write_en_2 : in  std_logic;
        C_data_in_2  : in  std_logic;
        C_busy_in_2  : in  std_logic;
        C_tag_in_2   : in  std_logic_vector(TAG_WIDTH-1 downto 0);

        Z_write_en_2 : in  std_logic;
        Z_data_in_2  : in  std_logic;
        Z_busy_in_2  : in  std_logic;
        Z_tag_in_2   : in  std_logic_vector(TAG_WIDTH-1 downto 0)
    );
end component;

component ARF is
    generic (
        DATA_WIDTH : integer := 16;
        TAG_WIDTH  : integer := 5
    );
    port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        
        R0_read_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        R0_write_en   : in  std_logic;
        R0_write_data : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        
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
end component ARF;

component instr_buffer is
    port (
        clk                     : in  std_logic;
        reset                   : in  std_logic; -- Active high
        
        -- Write Enables
        write_en_1              : in  std_logic;
        write_en_2              : in  std_logic;
        
        -- Input: Instruction 1 Slot
        in_Instr1               : in  std_logic_vector(15 downto 0);
        in_PC1                  : in  std_logic_vector(15 downto 0);
        in_PCnext_predicted1    : in  std_logic_vector(15 downto 0);
        in_valid1               : in  std_logic;
        
        -- Input: Instruction 2 Slot
        in_Instr2               : in  std_logic_vector(15 downto 0);
        in_PC2                  : in  std_logic_vector(15 downto 0);
        in_PCnext_predicted2    : in  std_logic_vector(15 downto 0);
        in_valid2               : in  std_logic;

        -- Output: Instruction 1 Slot
        out_Instr1              : out std_logic_vector(15 downto 0);
        out_PC1                 : out std_logic_vector(15 downto 0);
        out_PCnext_predicted1   : out std_logic_vector(15 downto 0);
        out_valid1              : out std_logic;
        
        -- Output: Instruction 2 Slot
        out_Instr2              : out std_logic_vector(15 downto 0);
        out_PC2                 : out std_logic_vector(15 downto 0);
        out_PCnext_predicted2   : out std_logic_vector(15 downto 0);
        out_valid2              : out std_logic
    );
end component;

component Data_Mem is -- byte addressing
	port( RA, WA, WD : in std_logic_vector(15 downto 0); -- accesses RA,WA and RA+1, WA+1 addresses
			DM_en : in std_logic;
			clk : in std_logic;
			RD : out std_logic_vector(15 downto 0));
end component;


component scheduler is
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

       alu_branch_valid    : out std_logic;
       alu_branch_opcode   : out std_logic_vector(3 downto 0);
       alu_branch_pc       : out std_logic_vector(15 downto 0);
       alu_branch_opr1     : out std_logic_vector(15 downto 0);
       alu_branch_opr2     : out std_logic_vector(15 downto 0);
       alu_branch_imm9     : out std_logic_vector(8 downto 0);
       alu_branch_dest_tag : out std_logic_vector(2 downto 0);

       alu_main_1_rob_idx     : out std_logic_vector(4 downto 0);
       alu_main_1_executing   : out std_logic;

       alu_main_2_rob_idx     : out std_logic_vector(4 downto 0);
       alu_main_2_executing   : out std_logic;

       alu_branch_rob_idx     : out std_logic_vector(4 downto 0);
       alu_branch_executing   : out std_logic
       );
end component;

component scheduler_buffer is
    Port (clk,en,reset : in  STD_LOGIC;      
			  D      : in  STD_LOGIC_VECTOR(196 downto 0); 
			  Q      : out STD_LOGIC_VECTOR(196 downto 0)  );
end component;

component Reservation_Station is
    generic (
        NUM_ENTRIES : integer := 32
    );
    port (
        clk            : in  std_logic;
        reset          : in  std_logic; 
        
        dispatch_we_1  : in  std_logic;
        dispatch_idx_1 : in  std_logic_vector(4 downto 0);
        dispatch_in_1  : in  rs_entry_t;
        dispatch_we_2  : in  std_logic;
        dispatch_idx_2 : in  std_logic_vector(4 downto 0);
        dispatch_in_2  : in  rs_entry_t;
        
        free_tag_1     : out std_logic_vector(4 downto 0);
        free_tag_2     : out std_logic_vector(4 downto 0);
        
        read_addr_1, read_addr_2, read_addr_3 : in  std_logic_vector(4 downto 0);
        read_row_1, read_row_2, read_row_3    : out rs_entry_t;
        v1_input, v2_input, v3_input          : in  std_logic; 
        
        rs_full        : out std_logic;
        ready_bits     : out std_logic_vector(NUM_ENTRIES-1 downto 0);

        cdb1_valid, cdb2_valid, cdb3_valid, cdb4_valid : in  std_logic;
        cdb1_tag, cdb2_tag, cdb3_tag, cdb4_tag         : in  std_logic_vector(4 downto 0);
        cdb1_value, cdb2_value, cdb3_value, cdb4_value : in  std_logic_vector(15 downto 0);

        cfcdb1_valid, cfcdb2_valid : in  std_logic;
        cfcdb1_tag, cfcdb2_tag     : in  std_logic_vector(4 downto 0);
        cfcdb1_value, cfcdb2_value : in  std_logic;

        zfcdb1_valid, zfcdb2_valid : in  std_logic;
        zfcdb1_tag, zfcdb2_tag     : in  std_logic_vector(4 downto 0);
        zfcdb1_value, zfcdb2_value : in  std_logic
    );
end component;

component Decode_Rename is
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
end component Decode_Rename;

component Load_Store_Queue is
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
end component;

component rob is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        flush_in : in  std_logic;

        ----------------------------------------------------------------
        -- DISPATCH (allocate entries) — slot 0 is older than slot 1
        ----------------------------------------------------------------
        disp0_valid        : in  std_logic;
        disp0_ip           : in  std_logic_vector(DATA_BITS-1 downto 0);
        disp0_r_dest       : in  std_logic_vector(ARCH_REGS-1 downto 0);
        disp0_renamed_reg  : in  std_logic_vector(TAG_BITS_RR-1 downto 0);
        disp0_old_dest_tag : in  std_logic_vector(TAG_BITS_RR-1 downto 0);
        disp0_is_branch    : in  std_logic;
        disp0_is_store     : in  std_logic;
        disp0_pred_taken   : in  std_logic;
        disp0_pred_target  : in  std_logic_vector(DATA_BITS-1 downto 0);

        disp1_valid        : in  std_logic;
        disp1_ip           : in  std_logic_vector(DATA_BITS-1 downto 0);
        disp1_r_dest       : in  std_logic_vector(ARCH_REGS-1 downto 0);
        disp1_renamed_reg  : in  std_logic_vector(TAG_BITS_RR-1 downto 0);
        disp1_old_dest_tag : in  std_logic_vector(TAG_BITS_RR-1 downto 0);
        disp1_is_branch    : in  std_logic;
        disp1_is_store     : in  std_logic;
        disp1_pred_taken   : in  std_logic;
        disp1_pred_target  : in  std_logic_vector(DATA_BITS-1 downto 0);

        rob_accept0 : out std_logic;
        rob_accept1 : out std_logic;

        ----------------------------------------------------------------
        -- COMMIT (up to 2 per cycle, strictly in-order)
        ----------------------------------------------------------------
        commit0_valid    : out std_logic;
        commit0_rrf_tag  : out std_logic_vector(TAG_BITS_RR-1 downto 0);
        commit0_old_tag  : out std_logic_vector(TAG_BITS_RR-1 downto 0);
        commit0_r_dest   : out std_logic_vector(ARCH_REGS-1 downto 0);
        commit0_value    : out std_logic_vector(DATA_BITS-1 downto 0);
        commit0_carry    : out std_logic;
        commit0_zero     : out std_logic;
        commit0_is_store : out std_logic;

        commit1_valid    : out std_logic;
        commit1_rrf_tag  : out std_logic_vector(TAG_BITS_RR-1 downto 0);
        commit1_old_tag  : out std_logic_vector(TAG_BITS_RR-1 downto 0);
        commit1_r_dest   : out std_logic_vector(ARCH_REGS-1 downto 0);
        commit1_value    : out std_logic_vector(DATA_BITS-1 downto 0);
        commit1_carry    : out std_logic;
        commit1_zero     : out std_logic;
        commit1_is_store : out std_logic;
		  commit0_old_tag_valid : out std_logic;
	     commit1_old_tag_valid : out std_logic;

        ----------------------------------------------------------------
        -- MISPREDICTION output
        ----------------------------------------------------------------
        flush      : out std_logic;
        correct_pc : out std_logic_vector(DATA_BITS-1 downto 0);

        ----------------------------------------------------------------
        -- ROB state visibility
        ----------------------------------------------------------------
        rob_array_out : out rob_array_t;
        rob_head_out  : out std_logic_vector(ROB_IDX-1 downto 0);
        rob_tail_out  : out std_logic_vector(ROB_IDX-1 downto 0);
		  
		  -- FROM SCHEDULER
		  sched_valid   : in std_logic;
		  sched_rob_idx : in std_logic_vector(ROB_IDX-1 downto 0);
		  
		  -- ALU pipe 0
		  exec0_valid   : in std_logic;
		  exec0_rob_idx : in std_logic_vector(ROB_IDX-1 downto 0);
		  exec0_value   : in std_logic_vector(DATA_BITS-1 downto 0);
		  exec0_carry   : in std_logic;
		  exec0_zero    : in std_logic;

		  -- ALU pipe 1
		  exec1_valid   : in std_logic;
		  exec1_rob_idx : in std_logic_vector(ROB_IDX-1 downto 0);
		  exec1_value   : in std_logic_vector(DATA_BITS-1 downto 0);
		  exec1_carry   : in std_logic;
		  exec1_zero    : in std_logic;
			
		  -- BRANCH pipe
		  exec2_valid   : in std_logic;
		  exec2_rob_idx : in std_logic_vector(ROB_IDX-1 downto 0);
		  exec2_taken   : in std_logic;
		  exec2_target  : in std_logic_vector(DATA_BITS-1 downto 0);

		  -- LOAD pipe
		  exec3_valid   : in std_logic;
		  exec3_rob_idx : in std_logic_vector(ROB_IDX-1 downto 0);
		  exec3_value   : in std_logic_vector(DATA_BITS-1 downto 0);
		
		  -- BRANCH INFO OUT (for mispredictor)
		  branch_valid        : out std_logic;
		  branch_bp_predicted : out std_logic;
		  branch_bp_target    : out std_logic_vector(DATA_BITS-1 downto 0);
		  branch_actual_taken : out std_logic;
		  branch_actual_target: out std_logic_vector(DATA_BITS-1 downto 0)
    );
end component;
--	-- PC signals
--	signal pc_value, pc_2_plus, pc_next : std_logic_vector(15 downto 0);
--	signal pc_en : std_logic;
--		-- Instruction memory outputs
--	signal instr_1_out, instr_2_out : std_logic_vector(15 downto 0);

    signal pc_value, pc_2_plus, pc_next : std_logic_vector(15 downto 0);
    signal pc_en                        : std_logic;
    signal instr_1_out, instr_2_out     : std_logic_vector(15 downto 0);

    -- Branch Predictor Outputs
    signal bp_pred_pc_s0, bp_pred_pc_s1 : std_logic_vector(15 downto 0);
    signal bp_next_pc                   : std_logic_vector(15 downto 0);
    signal bp_valid_s0, bp_valid_s1     : std_logic;
    signal bp_flush                     : std_logic;

    -- Instruction Buffer Outputs (pipeline from Instr_Mem -> Decode_Rename)
    signal out_instr1_wire, out_instr2_wire : std_logic_vector(15 downto 0);
    signal out_pc1_wire, out_pc2_wire       : std_logic_vector(15 downto 0);
    signal out_pcn1_wire, out_pcn2_wire     : std_logic_vector(15 downto 0);
    signal out_v1_wire, out_v2_wire         : std_logic;
    
    -- Structural Hazard Flags (from modules to Decode_Rename stall logic)
    signal rs_full_wire, lsq_full_wire      : std_logic;
    signal rrf_full_wire, c_full_wire, z_full_wire : std_logic;
    signal decode_stall                 : std_logic;

    -- ARF Read/Write (addresses from Decode_Rename to ARF)
    signal arf_read_addr_1, arf_read_addr_2, arf_read_addr_3, arf_read_addr_4 : std_logic_vector(2 downto 0);
    signal arf_rdata1, arf_rdata2, arf_rdata3, arf_rdata4 : std_logic_vector(15 downto 0);
    signal arf_rbusy1, arf_rbusy2, arf_rbusy3, arf_rbusy4 : std_logic;
    signal arf_rtag1, arf_rtag2, arf_rtag3, arf_rtag4 : std_logic_vector(4 downto 0);

    -- RRF Read/Write (rename consistency)
    signal rrf_rtag1, rrf_rtag2, rrf_rtag3, rrf_rtag4 : std_logic_vector(4 downto 0);
    signal rrf_rval1, rrf_rval2, rrf_rval3, rrf_rval4 : std_logic_vector(15 downto 0);
    signal rrf_rvalid1, rrf_rvalid2, rrf_rvalid3, rrf_rvalid4 : std_logic;
    signal rrf_free1, rrf_free2         : std_logic_vector(4 downto 0);
    signal rrf_fill1, rrf_fill2         : std_logic;

    -- CCF (Condition Codes)
    signal c_data, z_data               : std_logic;
    signal c_busy, z_busy               : std_logic;
    signal c_tag, z_tag                 : std_logic_vector(4 downto 0);

    -- Dispatch Signals (from Decode_Rename to RS/LSQ)
    signal rs_we1_wire, rs_we2_wire     : std_logic;
    signal rs_in1_wire, rs_in2_wire     : rs_entry_t;
    
    signal lsq_we1_wire, lsq_we2_wire   : std_logic;
    signal lsq_in1_wire, lsq_in2_wire   : rs_entry_t;

    signal ready_bits_wire              : std_logic_vector(31 downto 0);
    
    -- Scheduler to RS Read Port Wires
    signal sch_addr1, sch_addr2, sch_addr3 : std_logic_vector(4 downto 0);
    signal sch_row1, sch_row2, sch_row3    : rs_entry_t;
    signal v1_wire, v2_wire, v3_wire       : std_logic;

    -- ALU 1 Pipeline (197-bit Merged Path from Scheduler)
    signal alu1_merged                  : std_logic_vector(196 downto 0);
    signal alu1_buffered                : std_logic_vector(196 downto 0);
    signal alu1_en_wire                 : std_logic;

    -- ALU 2 Pipeline (197-bit Merged Path from Scheduler)
    signal alu2_merged                  : std_logic_vector(196 downto 0);
    signal alu2_buffered                : std_logic_vector(196 downto 0);
    signal alu2_en_wire                 : std_logic;

    -- ALU Branch Specific
    signal branch_taken                 : std_logic;
    signal branch_target                : std_logic_vector(15 downto 0);
    signal branch_dest_tag              : std_logic_vector(2 downto 0);
    signal branch_dest_valid            : std_logic;
    signal branch_dest_value            : std_logic_vector(15 downto 0);

    -- ALU Main Output Signals
    signal alu1_result                  : std_logic_vector(15 downto 0);
    signal alu1_z_flag_out              : std_logic;
    signal alu1_c_flag_out              : std_logic;
    signal alu1_dest_reg_valid          : std_logic;
    signal alu1_rob_idx                 : std_logic_vector(ROB_IDX-1 downto 0);
    signal alu1_valid_out               : std_logic;

    signal alu2_result                  : std_logic_vector(15 downto 0);
    signal alu2_z_flag_out              : std_logic;
    signal alu2_c_flag_out              : std_logic;
    signal alu2_dest_reg_valid          : std_logic;
    signal alu2_rob_idx                 : std_logic_vector(ROB_IDX-1 downto 0);
    signal alu2_valid_out               : std_logic;

    -- Scheduler Outputs for ROB Tracking
    signal sched_alu1_valid             : std_logic;
    signal sched_alu1_rob_idx           : std_logic_vector(ROB_IDX-1 downto 0);
    signal sched_alu2_valid             : std_logic;
    signal sched_alu2_rob_idx           : std_logic_vector(ROB_IDX-1 downto 0);
    signal sched_branch_valid           : std_logic;
    signal sched_branch_rob_idx         : std_logic_vector(ROB_IDX-1 downto 0);

    -- Data CDBs (Broadcasting Results) - 4 ALU Result Buses
    signal cdb1_valid, cdb2_valid, cdb3_valid, cdb4_valid : std_logic;
    signal cdb1_tag, cdb2_tag, cdb3_tag, cdb4_tag         : std_logic_vector(4 downto 0);
    signal cdb1_value, cdb2_value, cdb3_value, cdb4_value : std_logic_vector(15 downto 0);

    -- Carry Flag CDB
    signal cfcdb1_valid, cfcdb2_valid   : std_logic;
    signal cfcdb1_tag, cfcdb2_tag       : std_logic_vector(4 downto 0);
    signal cfcdb1_value, cfcdb2_value   : std_logic;

    -- Zero Flag CDB
    signal zfcdb1_valid, zfcdb2_valid   : std_logic;
    signal zfcdb1_tag, zfcdb2_tag       : std_logic_vector(4 downto 0);
    signal zfcdb1_value, zfcdb2_value   : std_logic;

    signal lsq_head_data                : rs_entry_t;
    signal lsq_head_ready               : std_logic;
    signal lsq_pop                      : std_logic;
    signal dm_read_data                 : std_logic_vector(15 downto 0);
    signal lsq_head_out                 : rs_entry_t;  -- LSQ head output (duplicate naming issue fix)

    -- ======== ROB (Reorder Buffer) Signal Declarations ========
    
    -- Dispatch Input Signals (from Decode_Rename)
    signal rob_disp0_valid              : std_logic;
    signal rob_disp0_ip                 : std_logic_vector(DATA_BITS-1 downto 0);
    signal rob_disp0_r_dest             : std_logic_vector(ARCH_REGS-1 downto 0);
    signal rob_disp0_renamed_reg        : std_logic_vector(TAG_BITS_RR-1 downto 0);
    signal rob_disp0_old_dest_tag       : std_logic_vector(TAG_BITS_RR-1 downto 0);
    signal rob_disp0_is_branch          : std_logic;
    signal rob_disp0_is_store           : std_logic;
    signal rob_disp0_pred_taken         : std_logic;
    signal rob_disp0_pred_target        : std_logic_vector(DATA_BITS-1 downto 0);

    signal rob_disp1_valid              : std_logic;
    signal rob_disp1_ip                 : std_logic_vector(DATA_BITS-1 downto 0);
    signal rob_disp1_r_dest             : std_logic_vector(ARCH_REGS-1 downto 0);
    signal rob_disp1_renamed_reg        : std_logic_vector(TAG_BITS_RR-1 downto 0);
    signal rob_disp1_old_dest_tag       : std_logic_vector(TAG_BITS_RR-1 downto 0);
    signal rob_disp1_is_branch          : std_logic;
    signal rob_disp1_is_store           : std_logic;
    signal rob_disp1_pred_taken         : std_logic;
    signal rob_disp1_pred_target        : std_logic_vector(DATA_BITS-1 downto 0);

    signal rob_accept0, rob_accept1     : std_logic;

    -- Execution Result Input Signals (from ALUs)
    -- ALU Main Pipe 0
    signal exec0_valid                  : std_logic;
    signal exec0_rob_idx                : std_logic_vector(ROB_IDX-1 downto 0);
    signal exec0_value                  : std_logic_vector(DATA_BITS-1 downto 0);
    signal exec0_carry                  : std_logic;
    signal exec0_zero                   : std_logic;

    -- ALU Main Pipe 1
    signal exec1_valid                  : std_logic;
    signal exec1_rob_idx                : std_logic_vector(ROB_IDX-1 downto 0);
    signal exec1_value                  : std_logic_vector(DATA_BITS-1 downto 0);
    signal exec1_carry                  : std_logic;
    signal exec1_zero                   : std_logic;

    -- ALU Branch Pipe
    signal exec2_valid                  : std_logic;
    signal exec2_rob_idx                : std_logic_vector(ROB_IDX-1 downto 0);
    signal exec2_taken                  : std_logic;
    signal exec2_target                 : std_logic_vector(DATA_BITS-1 downto 0);

    -- Load Pipe (from LSQ)
    signal exec3_valid                  : std_logic;
    signal exec3_rob_idx                : std_logic_vector(ROB_IDX-1 downto 0);
    signal exec3_value                  : std_logic_vector(DATA_BITS-1 downto 0);

    -- Scheduler Issue Tracking (from Scheduler)
    signal sched_valid                  : std_logic;
    signal sched_rob_idx                : std_logic_vector(ROB_IDX-1 downto 0);

    -- Commit Output Signals (to ARF & Mispredict Recovery)
    signal commit0_valid                : std_logic;
    signal commit0_rrf_tag              : std_logic_vector(TAG_BITS_RR-1 downto 0);
    signal commit0_old_tag              : std_logic_vector(TAG_BITS_RR-1 downto 0);
    signal commit0_r_dest               : std_logic_vector(ARCH_REGS-1 downto 0);
    signal commit0_value                : std_logic_vector(DATA_BITS-1 downto 0);
    signal commit0_carry                : std_logic;
    signal commit0_zero                 : std_logic;
    signal commit0_is_store             : std_logic;
    signal commit0_old_tag_valid        : std_logic;

    signal commit1_valid                : std_logic;
    signal commit1_rrf_tag              : std_logic_vector(TAG_BITS_RR-1 downto 0);
    signal commit1_old_tag              : std_logic_vector(TAG_BITS_RR-1 downto 0);
    signal commit1_r_dest               : std_logic_vector(ARCH_REGS-1 downto 0);
    signal commit1_value                : std_logic_vector(DATA_BITS-1 downto 0);
    signal commit1_carry                : std_logic;
    signal commit1_zero                 : std_logic;
    signal commit1_is_store             : std_logic;
    signal commit1_old_tag_valid        : std_logic;

    -- Flush & Branch Info Output Signals
    signal rob_flush                    : std_logic;
    signal rob_correct_pc               : std_logic_vector(DATA_BITS-1 downto 0);

    signal branch_valid_out             : std_logic;
    signal branch_bp_predicted_out      : std_logic;
    signal branch_bp_target_out         : std_logic_vector(DATA_BITS-1 downto 0);
    signal branch_actual_taken_out      : std_logic;
    signal branch_actual_target_out     : std_logic_vector(DATA_BITS-1 downto 0);

    -- ROB State Visibility (Debug/Inspection)
    signal rob_array_out                : rob_array_t;
    signal rob_head_out                 : std_logic_vector(ROB_IDX-1 downto 0);
    signal rob_tail_out                 : std_logic_vector(ROB_IDX-1 downto 0);

    -- ARF Write Port Signals (from ROB Commit)
    signal arf_we1_sig                  : std_logic;
    signal arf_addr1_sig                : std_logic_vector(ARCH_REGS-1 downto 0);
    signal arf_data1_sig                : std_logic_vector(DATA_BITS-1 downto 0);
    signal arf_tag1_sig                 : std_logic_vector(TAG_BITS_RR-1 downto 0);

    signal arf_we2_sig                  : std_logic;
    signal arf_addr2_sig                : std_logic_vector(ARCH_REGS-1 downto 0);
    signal arf_data2_sig                : std_logic_vector(DATA_BITS-1 downto 0);
    signal arf_tag2_sig                 : std_logic_vector(TAG_BITS_RR-1 downto 0);

    -- Branch Predictor Signals (from ROB)
    signal bp_mispredict_sig            : std_logic;
    signal bp_correct_pc_sig            : std_logic_vector(DATA_BITS-1 downto 0);

begin
	
--	instrmem: Instr_Mem		port map( pc_value, pc_2_plus, instr_1_out, instr_2_out);
--	pc_plus2: adder_2			port map( pc_value, pc_2_plus);
--	

    -- Branch Predictor
    bp_inst : branch_predictor 
        port map (
            clk                 => clk,
            rst                 => reset,
            fetch_pc            => pc_value,
            commit_mispredict   => bp_mispredict_sig,
            commit_correct_pc   => bp_correct_pc_sig,
            commit_upd0_en      => commit0_valid,
            commit_upd0_pc      => (others => '0'),
            commit_upd0_taken   => '0',
            commit_upd0_target  => (others => '0'),
            commit_upd1_en      => commit1_valid,
            commit_upd1_pc      => (others => '0'),
            commit_upd1_taken   => '0',
            commit_upd1_target  => (others => '0'),
            next_pc             => bp_next_pc,
            valid_s0            => bp_valid_s0,
            valid_s1            => bp_valid_s1,
            flush               => bp_flush
        );

    -- Instruction Memory
    instrmem : Instr_Mem 
        port map (
            RA1 => pc_value, 
            RA2 => pc_2_plus, 
            RD1 => instr_1_out, 
            RD2 => instr_2_out
        );

    -- Instruction Buffer
    instr_buff : instr_buffer
        port map (
            clk                  => clk,
            reset                => reset,
            write_en_1           => bp_valid_s0,
            write_en_2           => bp_valid_s1,
            in_Instr1            => instr_1_out,
            in_PC1               => pc_value,
            in_PCnext_predicted1 => bp_pred_pc_s0,
            in_valid1            => bp_valid_s0,
            in_Instr2            => instr_2_out,
            in_PC2               => pc_2_plus,
            in_PCnext_predicted2 => bp_pred_pc_s1,
            in_valid2            => bp_valid_s1,
            out_Instr1           => out_instr1_wire, -- To Rename/Decode
            out_PC1              => out_pc1_wire,
            out_PCnext_predicted1=> out_pcn1_wire,
            out_valid1           => out_v1_wire,
            out_Instr2           => out_instr2_wire,
            out_PC2              => out_pc2_wire,
            out_PCnext_predicted2=> out_pcn2_wire,
            out_valid2           => out_v2_wire
        );

    -- Decode and Rename
    dec_ren : Decode_Rename
        port map (
            clk                   => clk,
            reset                 => reset,
            in_Instr1             => out_instr1_wire,
            in_PC1                => out_pc1_wire,
            in_PCnext_predicted1  => out_pcn1_wire,
            in_valid1             => out_v1_wire,
            in_Instr2             => out_instr2_wire,
            in_PC2                => out_pc2_wire,
            in_PCnext_predicted2  => out_pcn2_wire,
            in_valid2             => out_v2_wire,
            rs_full               => rs_full_wire,
            lsq_full              => lsq_full_wire,
            rrf_full              => rrf_full_wire,
            frrf_c_full           => c_full_wire,
            frrf_z_full           => z_full_wire,
            decode_stall          => open,
            -- Connection to Reservation Station
            rs_dispatch_we_1      => rs_we1_wire,
            rs_dispatch_we_2      => rs_we2_wire,
            rs_dispatch_in_1      => rs_in1_wire,
            rs_dispatch_in_2      => rs_in2_wire,
            -- Connection to Load/Store Queue
            lsq_dispatch_we_1     => lsq_we1_wire,
            lsq_dispatch_we_2     => lsq_we2_wire,
            lsq_dispatch_in_1     => lsq_in1_wire,
            lsq_dispatch_in_2     => lsq_in2_wire,
            -- ARF Connections
            arf_read_addr_1       => arf_read_addr_1,
            arf_read_addr_2       => arf_read_addr_2,
            arf_read_addr_3       => arf_read_addr_3,
            arf_read_addr_4       => arf_read_addr_4,
            arf_read_data_1       => arf_rdata1,
            arf_read_data_2       => arf_rdata2,
            arf_read_data_3       => arf_rdata3,
            arf_read_data_4       => arf_rdata4,
            arf_read_busy_1       => arf_rbusy1,
            arf_read_busy_2       => arf_rbusy2,
            arf_read_busy_3       => arf_rbusy3,
            arf_read_busy_4       => arf_rbusy4,
            arf_read_tag_1        => arf_rtag1,
            arf_read_tag_2        => arf_rtag2,
            arf_read_tag_3        => arf_rtag3,
            arf_read_tag_4        => arf_rtag4,
            -- Other connections left open for your Logic
            rrf_read_tag_1        => rrf_rtag1,
            rrf_read_val_1        => rrf_rval1,
            rrf_read_valid_1      => rrf_rvalid1,
            rrf_free_tag_1        => rrf_free1,
            rrf_fill_1            => rrf_fill1,
            ccf_c_data            => c_data,
            ccf_c_busy            => c_busy,
            ccf_c_tag             => c_tag,
            ccf_z_data            => z_data,
            ccf_z_busy            => z_busy,
            ccf_z_tag             => z_tag,
            -- FRRF logic
            frrf_c_fill_1         => open,
            frrf_z_fill_1         => open
        );

    -- Register Files
    arf_inst : ARF
        port map (
            clk => clk, reset => reset,
            read_addr_1 => arf_read_addr_1, read_data_1 => arf_rdata1, read_busy_1 => arf_rbusy1, read_tag_1 => arf_rtag1,
            read_addr_2 => arf_read_addr_2, read_data_2 => arf_rdata2, read_busy_2 => arf_rbusy2, read_tag_2 => arf_rtag2,
            read_addr_3 => arf_read_addr_3, read_data_3 => arf_rdata3, read_busy_3 => arf_rbusy3, read_tag_3 => arf_rtag3,
            read_addr_4 => arf_read_addr_4, read_data_4 => arf_rdata4, read_busy_4 => arf_rbusy4, read_tag_4 => arf_rtag4,
            write_en_1 => arf_we1_sig, write_addr_1 => arf_addr1_sig, write_data_1 => arf_data1_sig, write_busy_1 => '0', write_tag_1 => arf_tag1_sig,
            write_en_2 => arf_we2_sig, write_addr_2 => arf_addr2_sig, write_data_2 => arf_data2_sig, write_busy_2 => '0', write_tag_2 => arf_tag2_sig
        );

    rrf_inst : RRF
        port map (
            clk => clk, reset => reset,
            read_tag_1 => rrf_rtag1, read_value_1 => rrf_rval1, read_busy_1 => open, read_valid_1 => rrf_rvalid1,
            free_tag_1_out => rrf_free1, fill_free_tag_1 => rrf_fill1, RRF_filled => rrf_full_wire,
            -- other ports open
            read_tag_2 => rrf_rtag2, read_value_2 => rrf_rval2, read_valid_2 => rrf_rvalid2,
            free_tag_2_out => rrf_free2, fill_free_tag_2 => rrf_fill2
        );

    -- Reservation Station & Scheduler
    res_station : Reservation_Station
        port map (
            clk => clk, reset => reset,
            dispatch_we_1 => rs_we1_wire, dispatch_idx_1 => open, dispatch_in_1 => rs_in1_wire,
            dispatch_we_2 => rs_we2_wire, dispatch_idx_2 => open, dispatch_in_2 => rs_in2_wire,
            free_tag_1 => open, free_tag_2 => open,
            rs_full => rs_full_wire, ready_bits => ready_bits_wire,
            read_addr_1 => sch_addr1, read_row_1 => sch_row1,
            read_addr_2 => sch_addr2, read_row_2 => sch_row2,
            read_addr_3 => sch_addr3, read_row_3 => sch_row3,
            v1_input => v1_wire, v2_input => v2_wire, v3_input => v3_wire,
            cdb1_valid => cdb1_valid, cdb2_valid => cdb2_valid, cdb3_valid => cdb3_valid, cdb4_valid => cdb4_valid,
            cdb1_tag => cdb1_tag, cdb2_tag => cdb2_tag, cdb3_tag => cdb3_tag, cdb4_tag => cdb4_tag,
            cdb1_value => cdb1_value, cdb2_value => cdb2_value, cdb3_value => cdb3_value, cdb4_value => cdb4_value,
            cfcdb1_valid => cfcdb1_valid, cfcdb2_valid => cfcdb2_valid,
            cfcdb1_tag => cfcdb1_tag, cfcdb2_tag => cfcdb2_tag,
            cfcdb1_value => cfcdb1_value, cfcdb2_value => cfcdb2_value,
            zfcdb1_valid => zfcdb1_valid, zfcdb2_valid => zfcdb2_valid,
            zfcdb1_tag => zfcdb1_tag, zfcdb2_tag => zfcdb2_tag,
            zfcdb1_value => zfcdb1_value, zfcdb2_value => zfcdb2_value
        );

    ls_queue : Load_Store_Queue
        port map (
            clk => clk, reset => reset,
            dispatch_we_1 => lsq_we1_wire, dispatch_in_1 => lsq_in1_wire,
            dispatch_we_2 => lsq_we2_wire, dispatch_in_2 => lsq_in2_wire,
            lsq_full => lsq_full_wire, head_data => lsq_head_data, head_ready => lsq_head_ready
        );

    sched : scheduler
        port map (
            ready_bits           => ready_bits_wire,
            read_addr_1          => sch_addr1, 
            read_addr_2          => sch_addr2, 
            read_addr_3          => sch_addr3,
            read_row_1           => sch_row1,
            read_row_2           => sch_row2,
            read_row_3           => sch_row3,
            v1_input             => v1_wire,
            v2_input             => v2_wire,
            v3_input             => v3_wire,
            -- Merging ALU 1 Output Ports into a single vector for the buffer
            alu_main_1_opcode    => alu1_merged(3 downto 0),
            alu_main_1_comp_bit  => alu1_merged(4),
            alu_main_1_cond      => alu1_merged(6 downto 5),
            alu_main_1_opr1      => alu1_merged(22 downto 7),
            alu_main_1_opr2      => alu1_merged(38 downto 23),
            alu_main_1_imm9      => alu1_merged(47 downto 39),
            alu_main_1_carry     => alu1_merged(48),
            alu_main_1_zero      => alu1_merged(49),
            alu_main_1_dest_tag  => alu1_merged(54 downto 50),
            -- ROB Index tracking from scheduler (OUTPUTS)
            alu_main_1_rob_idx   => sched_alu1_rob_idx,
            alu_main_1_executing => sched_alu1_valid,
            alu_main_1_valid     => alu1_en_wire,
            
            alu_main_2_valid     => alu2_en_wire,
            alu_main_2_rob_idx   => sched_alu2_rob_idx,
            alu_main_2_executing => sched_alu2_valid,
            
            alu_branch_valid     => sched_branch_valid,
            alu_branch_rob_idx   => sched_branch_rob_idx
        );

    -- ======== ROB (Reorder Buffer) Instantiation ========
    rob_inst : rob
        port map (
            clk                 => clk,
            rst                 => reset,
            flush_in            => '0',  -- Placeholder: will be driven by mispredict recovery
            
            -- ======== DISPATCH Ports ========
            disp0_valid         => rob_disp0_valid,
            disp0_ip            => rob_disp0_ip,
            disp0_r_dest        => rob_disp0_r_dest,
            disp0_renamed_reg   => rob_disp0_renamed_reg,
            disp0_old_dest_tag  => rob_disp0_old_dest_tag,
            disp0_is_branch     => rob_disp0_is_branch,
            disp0_is_store      => rob_disp0_is_store,
            disp0_pred_taken    => rob_disp0_pred_taken,
            disp0_pred_target   => rob_disp0_pred_target,
            
            disp1_valid         => rob_disp1_valid,
            disp1_ip            => rob_disp1_ip,
            disp1_r_dest        => rob_disp1_r_dest,
            disp1_renamed_reg   => rob_disp1_renamed_reg,
            disp1_old_dest_tag  => rob_disp1_old_dest_tag,
            disp1_is_branch     => rob_disp1_is_branch,
            disp1_is_store      => rob_disp1_is_store,
            disp1_pred_taken    => rob_disp1_pred_taken,
            disp1_pred_target   => rob_disp1_pred_target,
            
            rob_accept0         => rob_accept0,
            rob_accept1         => rob_accept1,
            
            -- ======== COMMIT Ports ========
            commit0_valid       => commit0_valid,
            commit0_rrf_tag     => commit0_rrf_tag,
            commit0_old_tag     => commit0_old_tag,
            commit0_r_dest      => commit0_r_dest,
            commit0_value       => commit0_value,
            commit0_carry       => commit0_carry,
            commit0_zero        => commit0_zero,
            commit0_is_store    => commit0_is_store,
            commit0_old_tag_valid => commit0_old_tag_valid,
            
            commit1_valid       => commit1_valid,
            commit1_rrf_tag     => commit1_rrf_tag,
            commit1_old_tag     => commit1_old_tag,
            commit1_r_dest      => commit1_r_dest,
            commit1_value       => commit1_value,
            commit1_carry       => commit1_carry,
            commit1_zero        => commit1_zero,
            commit1_is_store    => commit1_is_store,
            commit1_old_tag_valid => commit1_old_tag_valid,
            
            -- ======== MISPREDICTION & FLUSH ========
            flush               => rob_flush,
            correct_pc          => rob_correct_pc,
            
            -- ======== ROB State Visibility ========
            rob_array_out       => rob_array_out,
            rob_head_out        => rob_head_out,
            rob_tail_out        => rob_tail_out,
            
            -- ======== FROM SCHEDULER (Issue Tracking) ========
            sched_valid         => sched_alu1_valid,  -- Use ALU1 as primary tracker
            sched_rob_idx       => sched_alu1_rob_idx,
            
            -- ======== EXECUTION Ports (4 pipelines) ========
            -- ALU Main Pipe 0
            exec0_valid         => exec0_valid,
            exec0_rob_idx       => exec0_rob_idx,
            exec0_value         => exec0_value,
            exec0_carry         => exec0_carry,
            exec0_zero          => exec0_zero,
            
            -- ALU Main Pipe 1
            exec1_valid         => exec1_valid,
            exec1_rob_idx       => exec1_rob_idx,
            exec1_value         => exec1_value,
            exec1_carry         => exec1_carry,
            exec1_zero          => exec1_zero,
            
            -- Branch Pipe
            exec2_valid         => exec2_valid,
            exec2_rob_idx       => exec2_rob_idx,
            exec2_taken         => exec2_taken,
            exec2_target        => exec2_target,
            
            -- Load Pipe
            exec3_valid         => exec3_valid,
            exec3_rob_idx       => exec3_rob_idx,
            exec3_value         => exec3_value,
            
            -- ======== BRANCH INFO OUT (for Branch Predictor Training) ========
            branch_valid        => branch_valid_out,
            branch_bp_predicted => branch_bp_predicted_out,
            branch_bp_target    => branch_bp_target_out,
            branch_actual_taken => branch_actual_taken_out,
            branch_actual_target=> branch_actual_target_out
        );

    -- Scheduler Buffer (Placeholder for the 197-bit vector logic)
    sch_buf : scheduler_buffer
        port map (
            clk   => clk,
            en    => '1',
            reset => reset,
            D     => alu1_merged, -- 197-bit merged signals from scheduler
            Q     => alu1_buffered
        );

    -- Dual ALU Instantiation
    alu_1 : ALU_main
        port map (
            opcode           => alu1_buffered(3 downto 0),
            cond_bits        => alu1_buffered(6 downto 5),
            comp_bit         => alu1_buffered(4),
            operand_1        => alu1_buffered(22 downto 7),
            operand_2        => alu1_buffered(38 downto 23),
            imm_9            => alu1_buffered(47 downto 39),
            c_flag_in        => alu1_buffered(48),
            z_flag_in        => alu1_buffered(49),
            dest_tag_reg_in  => alu1_buffered(54 downto 50),
            result           => alu1_result,
            z_flag_out       => alu1_z_flag_out,
            c_flag_out       => alu1_c_flag_out,
            dest_tag_reg_out => open,
            dest_tag_z_out   => open,
            dest_tag_c_out   => open,
            dest_reg_valid   => alu1_dest_reg_valid,
            dest_z_valid     => open,
            dest_c_valid     => open
        );

    alu_2 : ALU_main
        port map (
            opcode           => alu2_buffered(3 downto 0),
            cond_bits        => alu2_buffered(6 downto 5),
            comp_bit         => alu2_buffered(4),
            operand_1        => alu2_buffered(22 downto 7),
            operand_2        => alu2_buffered(38 downto 23),
            imm_9            => alu2_buffered(47 downto 39),
            c_flag_in        => alu2_buffered(48),
            z_flag_in        => alu2_buffered(49),
            dest_tag_reg_in  => alu2_buffered(54 downto 50),
            result           => alu2_result,
            z_flag_out       => alu2_z_flag_out,
            c_flag_out       => alu2_c_flag_out,
            dest_tag_reg_out => open,
            dest_tag_z_out   => open,
            dest_tag_c_out   => open,
            dest_reg_valid   => alu2_dest_reg_valid,
            dest_z_valid     => open,
            dest_c_valid     => open
        );

    -- Misc
    pc_plus2: adder_2 port map( pc_value, pc_2_plus);		

    -- ======== COMBINATIONAL LOGIC FOR CONNECTIONS ========
    
    -- 1. DISPATCH PATH: Extract dispatch info from Decode_Rename outputs and route to ROB
    --    Source: rs_dispatch_in_1/2 from Decode_Rename (extracted to rs_in1_wire, rs_in2_wire)
    rob_disp0_valid       <= rs_we1_wire;                  -- Dispatch valid slot 0 (from Decode_Rename)
    rob_disp0_ip          <= rs_in1_wire.pc;               -- Instruction pointer from RS entry
    -- rob_disp0_r_dest, rob_disp0_renamed_reg, rob_disp0_old_dest_tag left open for Decode_Rename extraction
    -- rob_disp0_is_branch, rob_disp0_is_store, rob_disp0_pred_taken, rob_disp0_pred_target left open
    
    rob_disp1_valid       <= rs_we2_wire;                  -- Dispatch valid slot 1
    rob_disp1_ip          <= rs_in2_wire.pc;               -- Instruction pointer from RS entry

    -- 2. EXECUTION PATH 1: ALU_main_1 results to ROB exec0
    --    Source: Captured from alu_1 instance + scheduler tracking signals
    exec0_valid           <= sched_alu1_valid;             -- From scheduler (ALU1 executing)
    exec0_rob_idx         <= sched_alu1_rob_idx;           -- From scheduler (ALU1 ROB index)
    exec0_value           <= alu1_result;                  -- From ALU_main_1 result
    exec0_carry           <= alu1_c_flag_out;              -- From ALU_main_1 carry
    exec0_zero            <= alu1_z_flag_out;              -- From ALU_main_1 zero

    -- 3. EXECUTION PATH 2: ALU_main_2 results to ROB exec1
    --    Source: Captured from alu_2 instance + scheduler tracking signals
    exec1_valid           <= sched_alu2_valid;             -- From scheduler (ALU2 executing)
    exec1_rob_idx         <= sched_alu2_rob_idx;           -- From scheduler (ALU2 ROB index)
    exec1_value           <= alu2_result;                  -- From ALU_main_2 result
    exec1_carry           <= alu2_c_flag_out;              -- From ALU_main_2 carry
    exec1_zero            <= alu2_z_flag_out;              -- From ALU_main_2 zero

    -- 4. EXECUTION PATH 3: ALU_branch results to ROB exec2
    --    Source: branch_taken and branch_target from ALU_branch instance
    exec2_valid           <= sched_branch_valid;           -- From scheduler (Branch executing)
    exec2_rob_idx         <= sched_branch_rob_idx;         -- From scheduler (Branch ROB index)
    exec2_taken           <= branch_taken;                 -- From ALU_branch (take_branch output)
    exec2_target          <= branch_target;                -- From ALU_branch (target_address output)

    -- 5. EXECUTION PATH 4: Load results to ROB exec3 [STUB]
    --    Note: Stub for now - load execution path from LSQ not yet integrated
    --    Source: Will come from Load_Store_Queue execution unit (future)
    exec3_valid           <= '0';                          -- Placeholder
    exec3_rob_idx         <= (others => '0');              -- Placeholder
    exec3_value           <= (others => '0');              -- Placeholder

    -- 6. COMMIT PATH: Connect ROB commit outputs to ARF write port signals
    --    Destination: ARF write ports (routed via arf_we*_sig signals to arf_inst port map)
    arf_we1_sig           <= commit0_valid;                -- From ROB commit0_valid
    arf_addr1_sig         <= commit0_r_dest;               -- From ROB commit0_r_dest
    arf_data1_sig         <= commit0_value;                -- From ROB commit0_value
    arf_tag1_sig          <= commit0_rrf_tag;              -- From ROB commit0_rrf_tag
    
    arf_we2_sig           <= commit1_valid;                -- From ROB commit1_valid
    arf_addr2_sig         <= commit1_r_dest;               -- From ROB commit1_r_dest
    arf_data2_sig         <= commit1_value;                -- From ROB commit1_value
    arf_tag2_sig          <= commit1_rrf_tag;              -- From ROB commit1_rrf_tag

    -- 7. FLUSH PATH: Connect ROB flush signals to Branch Predictor via intermediate signals
    --    Source: ROB flush and correct_pc outputs
    --    Destination: Branch Predictor inputs (bp_mispredict_sig, bp_correct_pc_sig)
    bp_mispredict_sig     <= rob_flush;                    -- From ROB flush output
    bp_correct_pc_sig     <= rob_correct_pc;               -- From ROB correct_pc output
    
    -- 8. BRANCH TRAINING: Connect ROB branch info outputs to Mispredict Recovery module [FUTURE]
    --    Note: Full mispredict recovery training left open for integration
    --    Signals available: branch_valid_out, branch_bp_predicted_out, branch_bp_target_out,
    --                       branch_actual_taken_out, branch_actual_target_out
			
end architecture;			