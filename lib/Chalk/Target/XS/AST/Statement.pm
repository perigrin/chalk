# ABOUTME: XS AST node for raw C statements (e.g., "ObjectMAXFIELD(obj) = 0;")
# ABOUTME: Wraps arbitrary code as a statement for constructor and other low-level generation
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::Statement :isa(Chalk::Target::XS::AST::Node) {
    field $code :param :reader;

    method emit() {
        # If code ends with semicolon, use as-is; otherwise add semicolon
        if ($code =~ /;\s*$/) {
            return $code;
        }
        return "$code;";
    }
}

1;
