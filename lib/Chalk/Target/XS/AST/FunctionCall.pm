# ABOUTME: XS AST node for function calls
# ABOUTME: Represents internal function calls within the same XS module
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::Target::XS::AST::FunctionCall :isa(Chalk::Target::XS::AST::Node) {
    field $name :param :reader;      # Function name
    field $args :param :reader = []; # Argument variable names

    method emit() {
        my $arg_list = join(', ', $args->@*);
        return "$name($arg_list)";
    }
}

1;
