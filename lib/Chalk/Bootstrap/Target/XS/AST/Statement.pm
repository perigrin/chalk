# ABOUTME: XS AST node for raw C statements in CODE sections.
# ABOUTME: Emits indented C code lines, including multi-line call_method blocks.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target::XS::AST::Node;

class Chalk::Bootstrap::Target::XS::AST::Statement :isa(Chalk::Bootstrap::Target::XS::AST::Node) {
    field $code :param :reader;

    method emit() {
        return "    $code\n";
    }
}
