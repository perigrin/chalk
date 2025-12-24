# ABOUTME: Base class for XS AST nodes with abstract emit() method
# ABOUTME: All XS AST nodes inherit from this and implement emit() for code generation
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::Node {
    # Abstract base class for XS AST nodes
    # Subclasses must implement emit() to generate XS/C code

    method emit() {
        die "emit() not implemented in " . ref($self);
    }
}

1;
