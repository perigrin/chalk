# ABOUTME: XS AST node for C variable declarations (e.g., "NV x;" or "IV count = 0;")
# ABOUTME: Supports optional initialization with another AST node or string value
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::VarDecl :isa(Chalk::Target::XS::AST::Node) {
    field $type :param :reader;
    field $name :param :reader;
    field $init :param :reader = undef;

    method emit() {
        my $decl = "$type $name";

        if (defined $init) {
            # If init has an emit method, call it; otherwise use as string
            my $init_str = ref($init) && $init->can('emit') ? $init->emit() : $init;
            $decl .= " = $init_str";
        }

        return "$decl;";
    }
}

1;
