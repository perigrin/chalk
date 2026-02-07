# ABOUTME: XS AST node for a complete XSUB function with PREINIT/CODE/OUTPUT sections.
# ABOUTME: Partitions body nodes at emit time: VarDecls go to PREINIT, the rest to CODE.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target::XS::AST::Node;
use Chalk::Bootstrap::Target::XS::AST::VarDecl;

class Chalk::Bootstrap::Target::XS::AST::XSUB :isa(Chalk::Bootstrap::Target::XS::AST::Node) {
    field $return_type :param :reader = 'SV *';
    field $name :param :reader;
    field $params :param :reader;
    field $body :param :reader = [];

    method emit() {
        my $out = '';

        # Signature: return type on its own line
        $out .= "$return_type\n";

        # Function name with parameter names (not types) in parens
        # Extract bare name: "SV *self" → "self", "int count" → "count"
        my @param_names = map { my $p = (split /\s+/, $_)[-1]; $p =~ s/^\*//; $p } $params->@*;
        $out .= "$name(" . join(', ', @param_names) . ")\n";

        # Parameter declarations indented 4 spaces
        for my $param ($params->@*) {
            $out .= "    $param\n";
        }

        # Partition body: VarDecl nodes → PREINIT, everything else → CODE
        my @preinit;
        my @code;
        for my $node ($body->@*) {
            if ($node isa Chalk::Bootstrap::Target::XS::AST::VarDecl) {
                push @preinit, $node;
            } else {
                push @code, $node;
            }
        }

        # PREINIT section (only if there are VarDecl nodes)
        if (@preinit) {
            $out .= "  PREINIT:\n";
            for my $var (@preinit) {
                $out .= $var->emit();
            }
        }

        # CODE section
        $out .= "  CODE:\n";
        for my $stmt (@code) {
            $out .= $stmt->emit();
        }

        # OUTPUT section
        $out .= "  OUTPUT:\n";
        $out .= "    RETVAL\n";

        $out .= "\n";
        return $out;
    }
}
