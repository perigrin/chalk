# ABOUTME: XS AST node for MODULE/PACKAGE declarations in XS files
# ABOUTME: Generates "MODULE = X  PACKAGE = Y\n" header for XS code sections
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::Module :isa(Chalk::Target::XS::AST::Node) {
    field $module :param :reader;
    field $package :param :reader;

    method emit() {
        return "MODULE = $module  PACKAGE = $package\n";
    }
}

1;
