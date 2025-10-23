# ABOUTME: Example for Sea of Nodes Chapter 5 - If Statements with Phi Nodes
# ABOUTME: Demonstrates control flow with if-then-else, Region merging, and Phi nodes for value selection

use v5.42;

method classify($x) {
    if ($x > 0) {
        return 1;
    }
    return 0;
}

# Example calls (not yet implemented in IR):
# say classify(5);   # Would return 1 (positive)
# say classify(-3);  # Would return 0 (non-positive)
# say classify(0);   # Would return 0 (non-positive)
