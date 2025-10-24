#!/usr/bin/env perl
# ABOUTME: Sea of Nodes IR Chapter 7 example: Nested loop structures
# ABOUTME: Demonstrates nested loops with independent loop counters and phi nodes
use 5.42.0;

class NestedLoops {
    # Simple nested loop structure
    method nested_counter($n, $m) {
        my $i = 0;
        my $total = 0;
        while ($i < $n) {
            my $j = 0;
            while ($j < $m) {
                $total = $total + 1;
                $j = $j + 1;
            }
            $i = $i + 1;
        }
        return $total;
    }

    # Multiplication table using nested loops
    method multiply_table($rows, $cols) {
        my $r = 1;
        my $sum = 0;
        while ($r < $rows) {
            my $c = 1;
            while ($c < $cols) {
                $sum = $sum + ($r * $c);
                $c = $c + 1;
            }
            $r = $r + 1;
        }
        return $sum;
    }

    # Nested loop with early exit
    method find_pair($target) {
        my $i = 0;
        while ($i < 10) {
            my $j = 0;
            while ($j < 10) {
                if (($i + $j) == $target) {
                    return $i;
                }
                $j = $j + 1;
            }
            $i = $i + 1;
        }
        return 0;
    }
}

# Expected IR structure for nested_counter($n, $m):
#
# Outer Loop:
#   Loop_outer -> Phi_i [Loop_outer, 0, i+1]
#              -> Phi_total [Loop_outer, 0, total_from_inner]
#              -> If (i < n)
#                  |
#                  +-> IfTrue -> Inner Loop
#                  |
#                  +-> IfFalse -> Return (phi_total)
#
# Inner Loop (nested within IfTrue branch):
#   Loop_inner -> Phi_j [Loop_inner, 0, j+1]
#              -> Phi_total_inner [Loop_inner, phi_total, total+1]
#              -> If (j < m)
#                  |
#                  +-> IfTrue -> Add/Store -> (backedge to Loop_inner)
#                  |
#                  +-> IfFalse -> (continue to outer loop backedge)
#
# Scope management:
#   - Outer loop pushes scope for $i, $total
#   - Inner loop pushes nested scope for $j
#   - Inner loop can see outer variables but has own phi for $total
#   - When inner exits, scope pops back to outer loop scope

say "Chapter 7: Nested Loops with Scope Hierarchy";
say "Each loop creates its own scope level";
say "Inner loops can reference outer loop variables";
say "Each loop has independent phi nodes for its modified variables";
say "Scope stack ensures proper variable shadowing and lifetime";
