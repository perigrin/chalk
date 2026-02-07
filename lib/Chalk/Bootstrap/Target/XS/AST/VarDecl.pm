# ABOUTME: XS AST node for C variable declarations in PREINIT sections.
# ABOUTME: Emits indented type-name pairs like "    SV *symbol;".
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target::XS::AST::Node;

class Chalk::Bootstrap::Target::XS::AST::VarDecl :isa(Chalk::Bootstrap::Target::XS::AST::Node) {
    field $type :param :reader;
    field $name :param :reader;

    method emit() {
        # Omit space between pointer sigil and name (e.g. "SV *sym" not "SV * sym")
        my $sep = ($type =~ /\*$/) ? '' : ' ';
        return "    $type$sep$name;\n";
    }
}
