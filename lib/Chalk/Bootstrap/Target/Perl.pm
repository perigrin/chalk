# ABOUTME: Perl code emitter that walks IR nodes and produces feature class source.
# ABOUTME: Generates Chalk::Grammar::BNF::Generated equivalent to hand-written BNF.pm.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::Bootstrap::Target;

class Chalk::Bootstrap::Target::Perl :isa(Chalk::Bootstrap::Target) {

    method generate($ir) {
        my $body = $self->_emit_body($ir);

        return $self->_preamble() . $body . $self->_postamble();
    }

    method _preamble() {
        return <<'PREAMBLE';
# ABOUTME: Generated BNF meta-grammar from bootstrap compiler.
# ABOUTME: Equivalent to hand-written Chalk::Grammar::BNF.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Grammar::BNF::Generated {
    use Chalk::Grammar::Rule;
    use Chalk::Grammar::Symbol;

    sub grammar {
        my @rules;

PREAMBLE
    }

    method _emit_body($ir) {
        return '';
    }

    # Emit Perl source for a Constructor:Symbol IR node
    method _emit_symbol($symbol_node) {
        my $inputs = $symbol_node->inputs();
        my $type_str = $inputs->[0]->value();
        my $raw_value = $inputs->[1]->value();
        my $quant_node = $inputs->[2];
        my $quant_str = defined($quant_node) ? $quant_node->value() : undef;

        # Strip / delimiters from terminal values
        my $value = $raw_value;
        if ($type_str eq 'terminal' && $value =~ m{^/(.*)/$}) {
            $value = $1;
        }

        # Escape for single-quoted Perl strings
        $value = $self->_escape_single_quote($value);

        my $code = "Chalk::Grammar::Symbol->new(type => '$type_str', value => '$value'";
        if (defined $quant_str) {
            $code .= ", quantifier => '$quant_str'";
        }
        $code .= ')';

        return $code;
    }

    # Escape a string for embedding in a single-quoted Perl string literal
    method _escape_single_quote($str) {
        $str =~ s/\\/\\\\/g;   # \ -> \\
        $str =~ s/'/\\'/g;     # ' -> \'
        return $str;
    }

    method _postamble() {
        return <<'POSTAMBLE';
        return \@rules;
    }
}
POSTAMBLE
    }
}
