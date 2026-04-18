-- =============================================================================
-- File       : ras.vhd
-- Project    : IITB-RISC 2-way Superscalar Branch Predictor
-- Module     : Return Address Stack (RAS)
-- -----------------------------------------------------------------------------
-- Description:
--   Predicts return targets for JLR (Jump and Link to Register) instructions.
--
--   In IITB-RISC:
--     JAL  ra, Imm  -> acts as CALL  : push (PC+2) onto RAS
--     JLR  ra, rb   -> acts as RETURN: pop  RAS   for target prediction
--
--   The RAS is a circular stack with DEPTH entries. On overflow, the oldest
--   entry is silently overwritten. On underflow (pop on empty stack),
--   the pop is ignored and the empty flag is asserted.
--
--   Push/Pop are driven from the ID stage (target and call detection is
--   available after decode). This gives 1-cycle penalty for returns vs
--   4-cycle penalty if we wait until Execute.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ras is
    generic (
        DEPTH      : integer := 4;    -- Number of RAS entries
        ADDR_WIDTH : integer := 16
    );
    port (
        clk  : in std_logic;
        rst  : in std_logic;

        -- -----------------------------------------------------------------
        -- Push Interface  (activated in ID stage when a CALL is decoded)
        -- push_addr = PC+2 of the JAL/JLR-call instruction
        -- -----------------------------------------------------------------
        push_en   : in  std_logic;
        push_addr : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        -- -----------------------------------------------------------------
        -- Pop Interface  (activated in ID stage when a RETURN is decoded)
        -- top_addr = predicted return address
        -- -----------------------------------------------------------------
        pop_en   : in  std_logic;
        top_addr : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        empty    : out std_logic
    );
end entity ras;

architecture rtl of ras is

    type ras_array_t is array(0 to DEPTH-1) of std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal stack : ras_array_t;

    -- sp points to the NEXT free slot (0 = empty, DEPTH = full)
    signal sp : integer range 0 to DEPTH;

begin

    -- Peek at the top without popping (combinational)
    top_addr <= stack(sp-1) when sp > 0 else (others => '0');
    empty    <= '1' when sp = 0 else '0';

    process(clk, rst)
    begin
        if rst = '1' then
            sp    <= 0;
            stack <= (others => (others => '0'));

        elsif rising_edge(clk) then

            -- Push only
            if push_en = '1' and pop_en = '0' then
                if sp < DEPTH then
                    stack(sp) <= push_addr;
                    sp        <= sp + 1;
                else
                    -- Stack full: shift down and push (lose oldest entry)
                    for i in 0 to DEPTH-2 loop
                        stack(i) <= stack(i+1);
                    end loop;
                    stack(DEPTH-1) <= push_addr;
                    -- sp stays at DEPTH
                end if;

            -- Pop only
            elsif pop_en = '1' and push_en = '0' then
                if sp > 0 then
                    sp <= sp - 1;
                end if;
                -- Underflow: silently ignored (empty flag already '1')

            -- Simultaneous push and pop (tail-call optimisation: swap top)
            elsif push_en = '1' and pop_en = '1' then
                if sp > 0 then
                    -- Replace top with new return address
                    stack(sp-1) <= push_addr;
                else
                    -- Stack was empty: just push
                    stack(0) <= push_addr;
                    sp       <= 1;
                end if;

            end if;
        end if;
    end process;

end architecture rtl;
