# ABOUTME: XS AST node for binary operations (e.g., "a + b", "x * y")
# ABOUTME: Produces C binary expression with left operand, operator, and right operand
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::BinaryOp :isa(Chalk::Target::XS::AST::Node) {
    field $left :param :reader;
    field $operator :param :reader;
    field $right :param :reader;

    method emit() {
        return "$left $operator $right";
    }
}

1;
