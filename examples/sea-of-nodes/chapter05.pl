# ABOUTME: Example for Sea of Nodes Chapter 5 - If Statements with Phi Nodes
# ABOUTME: Demonstrates control flow with if-then-else, Region merging, and Phi nodes for value selection
use 5.42.0;

class Classifier {
    method classify($x) {
        if ($x > 0) {
            return 1;
        }
        return 0;
    }
}

# Example calls (not yet implemented in IR):
# my $classifier = Classifier->new();
# say $classifier->classify(5);   # Would return 1 (positive)
# say $classifier->classify(-3);  # Would return 0 (non-positive)
# say $classifier->classify(0);   # Would return 0 (non-positive)
