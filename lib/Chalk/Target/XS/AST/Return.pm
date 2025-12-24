# ABOUTME: XS AST node for return statements using RETVAL convention
# ABOUTME: Generates "RETVAL = expr;" for XS code returning values
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::Return :isa(Chalk::Target::XS::AST::Node) {
    field $expr :param :reader;

    method emit() {
        # If expr has an emit method, call it; otherwise use as string
        my $expr_str = ref($expr) && $expr->can('emit') ? $expr->emit() : $expr;
        return "RETVAL = $expr_str;";
    }
}

1;
