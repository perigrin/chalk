# ABOUTME: Example for Sea of Nodes Chapter 4 - Method Parameters
# ABOUTME: Demonstrates method signature with parameter and parameter usage in expressions
use 5.42.0;

class Calculator {
    method calculate($arg) {
        return $arg + 10;
    }
}

# Example call (not yet implemented in IR):
# my $calc = Calculator->new();
# say $calc->calculate(5);  # Would return 15
