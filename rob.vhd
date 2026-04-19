library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rob_pkg.all;

entity rob is
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
end entity;

architecture rtl of rob is

    signal rob_mem : rob_array_t := (others => ROB_ENTRY_RESET);
    signal head    : integer range 0 to ROB_DEPTH-1 := 0;
    signal tail    : integer range 0 to ROB_DEPTH-1 := 0;
    signal count   : integer range 0 to ROB_DEPTH   := 0;

begin

    ----------------------------------------------------------------
    -- ACCEPT LOGIC
    -- Block accepts during reset / external flush.
    ----------------------------------------------------------------
    rob_accept0 <= '1' when (
                        rst = '0' and
                        flush_in = '0' and
                        disp0_valid = '1' and
                        count < ROB_DEPTH
                   ) else '0';

    rob_accept1 <= '1' when (
                        rst = '0' and
                        flush_in = '0' and
                        disp1_valid = '1' and
                        (
                            (disp0_valid = '1' and count < ROB_DEPTH-1) or
                            (disp0_valid = '0' and count < ROB_DEPTH)
                        )
                   ) else '0';

    ----------------------------------------------------------------
    -- STATE EXPOSURE
    ----------------------------------------------------------------
    rob_array_out <= rob_mem;
    rob_head_out  <= std_logic_vector(to_unsigned(head, ROB_IDX));
    rob_tail_out  <= std_logic_vector(to_unsigned(tail, ROB_IDX));

    ----------------------------------------------------------------
    -- MAIN CLOCKED PROCESS
    ----------------------------------------------------------------
    process(clk)
        variable nxt           : rob_array_t;
        variable nxt_head      : integer range 0 to ROB_DEPTH-1;
        variable nxt_tail      : integer range 0 to ROB_DEPTH-1;
        variable nxt_count     : integer range 0 to ROB_DEPTH;
        variable flush_c0      : boolean;
        variable flush_now     : boolean;
		  variable idx           : integer range 0 to ROB_DEPTH-1;
    begin
        if rising_edge(clk) then

            ----------------------------------------------------------------
            -- RESET
            ----------------------------------------------------------------
            if rst = '1' then
                rob_mem <= (others => ROB_ENTRY_RESET);
                head    <= 0;
                tail    <= 0;
                count   <= 0;

                flush          <= '0';
                correct_pc     <= (others => '0');

                commit0_valid    <= '0';
                commit0_rrf_tag  <= (others => '0');
                commit0_old_tag  <= (others => '0');
                commit0_r_dest   <= (others => '0');
                commit0_value    <= (others => '0');
                commit0_carry    <= '0';
                commit0_zero     <= '0';
                commit0_is_store <= '0';

                commit1_valid    <= '0';
                commit1_rrf_tag  <= (others => '0');
                commit1_old_tag  <= (others => '0');
                commit1_r_dest   <= (others => '0');
                commit1_value    <= (others => '0');
                commit1_carry    <= '0';
                commit1_zero     <= '0';
                commit1_is_store <= '0';
					 commit0_old_tag_valid <= '0';
					 commit1_old_tag_valid <= '0';

					 branch_valid         <= '0';
					 branch_bp_predicted  <= '0';
					 branch_bp_target     <= (others => '0');
					 branch_actual_taken  <= '0';
					 branch_actual_target <= (others => '0');

            ----------------------------------------------------------------
            -- EXTERNAL FLUSH
            ----------------------------------------------------------------
            elsif flush_in = '1' then
                rob_mem <= (others => ROB_ENTRY_RESET);
                head    <= 0;
                tail    <= 0;
                count   <= 0;

                flush          <= '0';
                correct_pc     <= (others => '0');

                commit0_valid    <= '0';
                commit0_rrf_tag  <= (others => '0');
                commit0_old_tag  <= (others => '0');
                commit0_r_dest   <= (others => '0');
                commit0_value    <= (others => '0');
                commit0_carry    <= '0';
                commit0_zero     <= '0';
                commit0_is_store <= '0';

                commit1_valid    <= '0';
                commit1_rrf_tag  <= (others => '0');
                commit1_old_tag  <= (others => '0');
                commit1_r_dest   <= (others => '0');
                commit1_value    <= (others => '0');
                commit1_carry    <= '0';
                commit1_zero     <= '0';
                commit1_is_store <= '0';
					 commit0_old_tag_valid <= '0';
					 commit1_old_tag_valid <= '0';

					 branch_valid         <= '0';
					 branch_bp_predicted  <= '0';
					 branch_bp_target     <= (others => '0');
					 branch_actual_taken  <= '0';
					 branch_actual_target <= (others => '0');

            else
                nxt       := rob_mem;
                nxt_head  := head;
                nxt_tail  := tail;
                nxt_count := count;
                flush_c0  := false;
                flush_now := false;

                ----------------------------------------------------------------
                -- DEFAULT OUTPUTS
                ----------------------------------------------------------------
                flush      <= '0';
                correct_pc <= (others => '0');

                commit0_valid    <= '0';
                commit0_rrf_tag  <= (others => '0');
                commit0_old_tag  <= (others => '0');
                commit0_r_dest   <= (others => '0');
                commit0_value    <= (others => '0');
                commit0_carry    <= '0';
                commit0_zero     <= '0';
                commit0_is_store <= '0';

                commit1_valid    <= '0';
                commit1_rrf_tag  <= (others => '0');
                commit1_old_tag  <= (others => '0');
                commit1_r_dest   <= (others => '0');
                commit1_value    <= (others => '0');
                commit1_carry    <= '0';
                commit1_zero     <= '0';
                commit1_is_store <= '0';
					 commit0_old_tag_valid <= '0';
					 commit1_old_tag_valid <= '0';
					 branch_valid         <= '0';
				 	 branch_bp_predicted  <= '0';
					 branch_bp_target     <= (others => '0');
					 branch_actual_taken  <= '0';
					 branch_actual_target <= (others => '0');

					 ----------------------------------------------------------------
					 -- ISSUE UPDATE (from scheduler)
					 ----------------------------------------------------------------
					 if sched_valid = '1' then
						  idx := to_integer(unsigned(sched_rob_idx));
						  if nxt(idx).busy = '1' then
							   nxt(idx).issue := '1';
						  end if;
					 end if;
					 ----------------------------------------------------------------
					 -- EXECUTE UPDATE : ALU pipe 0
					 ----------------------------------------------------------------
					 if exec0_valid = '1' then
					 	  idx := to_integer(unsigned(exec0_rob_idx));
						  if nxt(idx).busy = '1' then
							   nxt(idx).exe       := '1';
							   nxt(idx).completed := '1';
							   nxt(idx).value1    := exec0_value;
							   nxt(idx).carry     := exec0_carry;
							   nxt(idx).zero      := exec0_zero;
						  end if;
					 end if;
					 ----------------------------------------------------------------
					 -- EXECUTE UPDATE : ALU pipe 1
					 ----------------------------------------------------------------
					 if exec1_valid = '1' then
						  idx := to_integer(unsigned(exec1_rob_idx));
						  if nxt(idx).busy = '1' then
							   nxt(idx).exe       := '1';
							   nxt(idx).completed := '1';
							   nxt(idx).value1    := exec1_value;
							   nxt(idx).carry     := exec1_carry;
							   nxt(idx).zero      := exec1_zero;
						  end if;
					 end if;
					 ----------------------------------------------------------------
					 -- EXECUTE UPDATE : BRANCH pipe
					 ----------------------------------------------------------------
					 if exec2_valid = '1' then
						  idx := to_integer(unsigned(exec2_rob_idx));
						  if nxt(idx).busy = '1' then
							   nxt(idx).exe           := '1';
							   nxt(idx).completed     := '1';
							   nxt(idx).actual_taken  := exec2_taken;
							   nxt(idx).actual_target := exec2_target;
						  end if;
					 end if;
					 ----------------------------------------------------------------
					 -- EXECUTE UPDATE : LOAD pipe
					 ----------------------------------------------------------------
					 if exec3_valid = '1' then
						  idx := to_integer(unsigned(exec3_rob_idx));
						  if nxt(idx).busy = '1' then
							   nxt(idx).exe       := '1';
							   nxt(idx).completed := '1';
							   nxt(idx).value1    := exec3_value;
						  end if;
					 end if;
                ----------------------------------------------------------------
                -- COMMIT 0
                ----------------------------------------------------------------
					 
                if nxt(nxt_head).busy = '1' and nxt(nxt_head).completed = '1' then

                    commit0_valid    <= '1';
						  
						  if nxt(nxt_head).is_branch = '1' then
							   branch_valid         <= '1';
							   branch_bp_predicted  <= nxt(nxt_head).bp_predicted;
							   branch_bp_target     <= nxt(nxt_head).bp_target;
							   branch_actual_taken  <= nxt(nxt_head).actual_taken;
							   branch_actual_target <= nxt(nxt_head).actual_target;
						  else
							   branch_valid <= '0';
						  end if;
					 
                    commit0_rrf_tag  <= nxt(nxt_head).renamed_reg;
                    commit0_r_dest   <= nxt(nxt_head).r_dest;
                    commit0_value    <= nxt(nxt_head).value1;
                    commit0_carry    <= nxt(nxt_head).carry;
                    commit0_zero     <= nxt(nxt_head).zero;
                    commit0_is_store <= nxt(nxt_head).is_store;

						  if nxt(nxt_head).old_dest_tag_valid = '1' then
							   commit0_old_tag       <= nxt(nxt_head).old_dest_tag;
							   commit0_old_tag_valid <= '1';
						  else
							   commit0_old_tag       <= (others => '0');
							   commit0_old_tag_valid <= '0';
						  end if;
                    nxt(nxt_head).busy         := '0';
                    nxt(nxt_head).completed    := '0';

                    nxt_head  := (nxt_head + 1) mod ROB_DEPTH;
                    nxt_count := nxt_count - 1;

                    ----------------------------------------------------------------
                    -- COMMIT 1 only if commit0 did not mispredict
                    ----------------------------------------------------------------
                    if not flush_c0 then
                        if nxt(nxt_head).busy = '1' and nxt(nxt_head).completed = '1' then

                            commit1_valid    <= '1';
                            commit1_rrf_tag  <= nxt(nxt_head).renamed_reg;
									 commit1_r_dest   <= nxt(nxt_head).r_dest;
                            commit1_value    <= nxt(nxt_head).value1;
                            commit1_carry    <= nxt(nxt_head).carry;
                            commit1_zero     <= nxt(nxt_head).zero;
                            commit1_is_store <= nxt(nxt_head).is_store;

									 if nxt(nxt_head).old_dest_tag_valid = '1' then
										  commit1_old_tag       <= nxt(nxt_head).old_dest_tag;
										  commit1_old_tag_valid <= '1';
									 else
										  commit1_old_tag       <= (others => '0');
										  commit1_old_tag_valid <= '0';
									 end if;
                            nxt(nxt_head).busy         := '0';
                            nxt(nxt_head).completed    := '0';

                            nxt_head  := (nxt_head + 1) mod ROB_DEPTH;
                            nxt_count := nxt_count - 1;
                        end if;
                    end if;
                end if;

                ----------------------------------------------------------------
                -- INTERNAL MISPREDICT FLUSH
                -- If a committed branch mispredicts, all younger instructions
                -- must be squashed immediately. No dispatch in that same cycle.
                ----------------------------------------------------------------
                if flush_now then
                    nxt       := (others => ROB_ENTRY_RESET);
                    nxt_head  := 0;
                    nxt_tail  := 0;
                    nxt_count := 0;

                else
                    ----------------------------------------------------------------
                    -- DISPATCH 0
                    ----------------------------------------------------------------
                    if disp0_valid = '1' and nxt_count < ROB_DEPTH then
                        nxt(nxt_tail)              := ROB_ENTRY_RESET;
                        nxt(nxt_tail).busy         := '1';
                        nxt(nxt_tail).ip           := disp0_ip;
                        nxt(nxt_tail).r_dest       := disp0_r_dest;
                        nxt(nxt_tail).renamed_reg  := disp0_renamed_reg;
								nxt(nxt_tail).old_dest_tag := disp0_old_dest_tag;
								-- VALID LOGIC
								if disp0_is_store = '0' and disp0_is_branch = '0' then
									 nxt(nxt_tail).old_dest_tag_valid := '1';
								else
									 nxt(nxt_tail).old_dest_tag_valid := '0';
								end if;
                        nxt(nxt_tail).is_branch    := disp0_is_branch;
                        nxt(nxt_tail).is_store     := disp0_is_store;
                        nxt(nxt_tail).bp_predicted := disp0_pred_taken;
                        nxt(nxt_tail).bp_target    := disp0_pred_target;
                        nxt_tail  := (nxt_tail + 1) mod ROB_DEPTH;
                        nxt_count := nxt_count + 1;
                    end if;

                    ----------------------------------------------------------------
                    -- DISPATCH 1
                    ----------------------------------------------------------------
                    if disp1_valid = '1' and nxt_count < ROB_DEPTH then
                        nxt(nxt_tail)              := ROB_ENTRY_RESET;
                        nxt(nxt_tail).busy         := '1';
                        nxt(nxt_tail).ip           := disp1_ip;
                        nxt(nxt_tail).r_dest       := disp1_r_dest;
                        nxt(nxt_tail).renamed_reg  := disp1_renamed_reg;
								nxt(nxt_tail).old_dest_tag := disp1_old_dest_tag;
								if disp1_is_store = '0' and disp1_is_branch = '0' then
									 nxt(nxt_tail).old_dest_tag_valid := '1';
								else
									 nxt(nxt_tail).old_dest_tag_valid := '0';
								end if;
                        nxt(nxt_tail).is_branch    := disp1_is_branch;
                        nxt(nxt_tail).is_store     := disp1_is_store;
                        nxt(nxt_tail).bp_predicted := disp1_pred_taken;
                        nxt(nxt_tail).bp_target    := disp1_pred_target;
                        nxt_tail  := (nxt_tail + 1) mod ROB_DEPTH;
                        nxt_count := nxt_count + 1;
                    end if;
                end if;

                ----------------------------------------------------------------
                -- STATE UPDATE
                ----------------------------------------------------------------
                rob_mem <= nxt;
                head    <= nxt_head;
                tail    <= nxt_tail;
                count   <= nxt_count;

            end if;
        end if;
    end process;

end architecture;


