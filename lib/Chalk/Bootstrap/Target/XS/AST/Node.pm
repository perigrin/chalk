# ABOUTME: Abstract base class for all XS AST nodes.
# ABOUTME: Subclasses implement emit() to produce XS text fragments.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::Target::XS::AST::Node {
    method emit() {
        die "Subclass must implement emit()";
    }
}
