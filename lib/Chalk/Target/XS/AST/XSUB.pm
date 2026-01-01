# ABOUTME: XS AST node for XSUB function declarations with parameters and body
# ABOUTME: Generates complete XSUB with signature, CODE section, and OUTPUT section
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::XSUB :isa(Chalk::Target::XS::AST::Node) {
    field $name :param :reader;
    field $params :param :reader = [];
    field $body :param :reader = [];
    field $return_type :param :reader = 'NV';

    method emit() {
        my $output = "";

        # Function signature: RETURN_TYPE function_name(PARAMS)
        # Strip Perl sigils from parameter names for C/XS
        my @bare_params = map { s/^[\$\@\%]//r } $params->@*;
        my $params_str = join(', ', @bare_params);
        $output .= "$return_type $name($params_str)\n";

        # CODE section
        $output .= "CODE:\n";

        # Emit body statements
        for my $stmt ($body->@*) {
            my $stmt_str = ref($stmt) && $stmt->can('emit') ? $stmt->emit() : $stmt;
            $output .= "    $stmt_str\n";
        }

        # OUTPUT section
        $output .= "OUTPUT:\n";
        $output .= "    RETVAL\n";

        return $output;
    }
}

1;
