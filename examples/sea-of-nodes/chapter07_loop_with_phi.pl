#!/usr/bin/env perl
# ABOUTME: Sea of Nodes IR Chapter 7 example: Loops with multiple phi nodes
# ABOUTME: Demonstrates loop-carried dependencies and phi node generation for multiple variables
use 5.42.0;

class MultiVariableLoop {
    # Loop with two modified variables
    # Both $i and $sum need phi nodes
    method sum_to_n($n) {
        my $i = 0;
        my $sum = 0;
        while ($i < $n) {
            $sum = $sum + $i;
            $i = $i + 1;
        }
        return $sum;
    }

    # Loop with three modified variables
    method fibonacci($n) {
        my $i = 0;
        my $a = 0;
        my $b = 1;
        while ($i < $n) {
            my $temp = $a + $b;
            $a = $b;
            $b = $temp;
            $i = $i + 1;
        }
        return $a;
    }

    # Loop where only some variables are modified
    method selective_update($limit) {
        my $i = 0;
        my $total = 0;
        my $max = 100;  # Not modified - no phi needed
        while ($i < $limit) {
            if ($i < $max) {
                $total = $total + $i;
            }
            $i = $i + 1;
        }
        return $total;
    }
}

# Expected IR structure for sum_to_n($n):
#
# Loop node with two phi nodes:
#   Phi_i:   [Loop, Constant(0), Add(i+1)]
#   Phi_sum: [Loop, Constant(0), Add(sum+i)]
#
# The loop tracking system automatically detects:
#   - Variables defined before loop: $i, $sum, $n
#   - Variables modified in loop: $i, $sum
#   - Variables unchanged: $n (loop limit, no phi needed)
#
# For each modified variable:
#   1. Snapshot binding at loop entry
#   2. Track modifications during loop body
#   3. Generate phi node with [control, initial, backedge]
#   4. Update scope to use phi for loop body references

say "Chapter 7: Multiple Phi Nodes in Loops";
say "Loop tracking detects all modified variables automatically";
say "Only modified variables get phi nodes - unchanged vars don't";
say "Each phi merges initial value with loop-updated value";
