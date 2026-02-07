# ABOUTME: XS AST node for MODULE/PACKAGE declaration in XS files.
# ABOUTME: Emits the MODULE = X  PACKAGE = Y line that establishes the Perl namespace.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target::XS::AST::Node;

class Chalk::Bootstrap::Target::XS::AST::Module :isa(Chalk::Bootstrap::Target::XS::AST::Node) {
    field $module :param :reader;
    field $package :param :reader;

    method emit() {
        return "MODULE = $module  PACKAGE = $package\n\n";
    }
}
