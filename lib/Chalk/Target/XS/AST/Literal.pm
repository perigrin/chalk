# ABOUTME: XS AST node representing literal values (integers, floats, strings)
# ABOUTME: Emits the literal value with appropriate formatting for C code
use 5.42.0;
use experimental qw(class);
use Scalar::Util ();

class Chalk::Target::XS::AST::Literal :isa(Chalk::Target::XS::AST::Node) {
    field $value :param :reader;

    method emit() {
        # If value is a number, emit as-is
        # If value is a string, emit with double quotes
        if (Scalar::Util::looks_like_number($value)) {
            return "$value";
        } else {
            return qq("$value");
        }
    }
}

1;
