# ABOUTME: XS code emitter that walks IR nodes and produces XS source.
# ABOUTME: Generates .xs file with XSUBs that construct grammar rules via call_method.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::Bootstrap::Target;
use Chalk::Bootstrap::Target::XS::AST::Preamble;
use Chalk::Bootstrap::Target::XS::AST::Module;
use Chalk::Bootstrap::Target::XS::AST::CompositeNode;

class Chalk::Bootstrap::Target::XS :isa(Chalk::Bootstrap::Target) {
    field $module_name :param :reader = 'Chalk::Grammar::BNF::Rules';

    # Escape a string for embedding in a C double-quoted string literal
    method _escape_c_string($str) {
        $str =~ s/\\/\\\\/g;   # \ -> \\
        $str =~ s/"/\\"/g;     # " -> \"
        return $str;
    }

    # Strip / delimiters from terminal regex values
    method _strip_terminal_delimiters($value) {
        if ($value =~ m{^/(.*)/$}) {
            return $1;
        }
        return $value;
    }

    # Emit a C expression for an IR Constant node
    method _emit_constant($node) {
        my $value = $node->value();
        my $escaped = $self->_escape_c_string($value);
        return "newSVpvs(\"$escaped\")";
    }

    method generate($ir) {
        die "generate() requires an arrayref of IR rules"
            unless defined($ir) && ref($ir) eq 'ARRAY';

        my $preamble = Chalk::Bootstrap::Target::XS::AST::Preamble->new();
        my $module = Chalk::Bootstrap::Target::XS::AST::Module->new(
            module  => $module_name,
            package => $module_name,
        );

        my $composite = Chalk::Bootstrap::Target::XS::AST::CompositeNode->new(
            children => [$preamble, $module],
        );

        return $composite->emit();
    }
}
