#!/usr/bin/env perl
# ABOUTME: Sea of Nodes IR Chapter 6 example: Dead Control Flow Elimination
# ABOUTME: Demonstrates constant condition optimization and dead code elimination

use v5.42;

# Example 1: Constant true condition - dead else branch
method always_true() {
    if (1) {
        return 42;
    }
    return 0;  # Dead code - never reached
}

# Example 2: Constant false condition - dead then branch
method always_false() {
    if (0) {
        return 42;  # Dead code - never reached
    }
    return 0;
}

# Example 3: Constant comparison - always true
method constant_comparison($x) {
    if (5 > 3) {
        return $x + 10;
    }
    return $x;  # Dead code
}

# Example 4: Variable condition - no optimization
method variable_condition($x) {
    if ($x > 0) {
        return 1;
    }
    return 0;
}

# Optimized IR for always_true() should be:
# Start -> Proj (ctrl) -> Return (42)
# The If, false branch, and return 0 should be eliminated

say "Chapter 6: Dead Control Flow Elimination";
say "Constant conditions enable branch elimination";
say "Dead branches are marked with ~Ctrl constant";
say "Region/Phi nodes simplify when branches are dead";
