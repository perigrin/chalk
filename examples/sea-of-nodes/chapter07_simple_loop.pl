#!/usr/bin/env perl
# ABOUTME: Sea of Nodes IR Chapter 7 example: Simple counting loop
# ABOUTME: Demonstrates basic while loop with loop counter and Loop/Phi nodes
use 5.42.0;

class SimpleLoop {
    # Simple counting loop: while ($i < 10) { $i = $i + 1; }
    method count_to_ten() {
        my $i = 0;
        while ($i < 10) {
            $i = $i + 1;
        }
        return $i;
    }

    # Countdown loop: while ($n > 0) { $n = $n - 1; }
    method countdown($n) {
        while ($n > 0) {
            $n = $n - 1;
        }
        return $n;
    }

    # Loop with constant true condition (infinite loop pattern)
    method infinite_loop() {
        my $x = 1;
        while (1) {
            $x = $x + 1;
            if ($x > 100) {
                last;  # Break out of loop
            }
        }
        return $x;
    }
}

# Expected IR structure for count_to_ten():
#
# Start -> Loop (entry) -> If (i < 10)
#   |                       |
#   |                       +-> IfTrue -> Add (i + 1) -> Store (i)
#   |                       |                              |
#   |                       |                              +-> (backedge to Loop)
#   |                       |
#   +-> Constant(0) --------+-> IfFalse -> Region (exit) -> Return (phi_i)
#
# Loop Phi node for $i:
#   inputs: [Loop, Constant(0), Add_result]
#   Merges: initial value (0) with loop update (i + 1)

say "Chapter 7: Simple Loops with Loop and Phi nodes";
say "Loop nodes represent loop headers with entry + backedge control";
say "Loop Phi nodes merge initial values with loop-updated values";
