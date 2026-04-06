# ABOUTME: Perl code emitter that walks IR nodes and produces feature class source.
# ABOUTME: Generates Chalk::Grammar::BNF::Generated equivalent to hand-written BNF.pm.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;

class Chalk::Bootstrap::BNF::Target::Perl :isa(Chalk::Bootstrap::Target) {

    method generate($ir) {
        die "generate() requires an arrayref of IR rules"
            unless defined($ir) && ref($ir) eq 'ARRAY';

        my $body = $self->_emit_body($ir);

        return $self->_preamble() . $body . $self->_postamble();
    }

    method _preamble() {
        return q[# ABOUTME: Generated BNF meta-grammar from bootstrap compiler.
# ABOUTME: Equivalent to hand-written Chalk::Grammar::BNF.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::BNF::Generated {
    use Chalk::Grammar::Rule;
    use Chalk::Grammar::Symbol;

    sub grammar {
        my @rules;

];
    }

    method _emit_body($ir) {
        my $body = '';
        for my $rule ($ir->@*) {
            $body .= $self->_emit_rule($rule) . "\n";
        }
        return $body;
    }

    # Emit Perl source for a Chalk::Grammar::Symbol object
    method _emit_symbol($symbol_node) {
        my $type_str  = $symbol_node->type();
        my $raw_value = $symbol_node->value();
        my $quant_str = $symbol_node->quantifier();

        # Strip / delimiters from terminal values
        my $value = $raw_value;
        if ($type_str eq 'terminal' && $value =~ m{^/(.*)/$}) {
            $value = $1;
        }

        # Escape for single-quoted Perl strings
        $value = $self->_escape_single_quote($value);

        my $code = "Chalk::Grammar::Symbol->new(type => '$type_str', value => '$value'";
        if (defined $quant_str) {
            $code .= ", quantifier => '" . $self->_escape_single_quote($quant_str) . "'";
        }
        $code .= ')';

        return $code;
    }

    # Emit Perl source for an expression (arrayref of Chalk::Grammar::Symbol objects)
    method _emit_expression($expr_node) {
        my $elements = $expr_node;
        my @symbol_codes;
        for my $sym ($elements->@*) {
            push @symbol_codes, $self->_emit_symbol($sym);
        }

        return "[\n" . join(",\n", map { "                $_ " } @symbol_codes) . ",\n            ]";
    }

    # Emit Perl source for a Chalk::Grammar::Rule object
    method _emit_rule($rule_node) {
        my $name        = $rule_node->name();
        my $expressions = $rule_node->expressions();

        my @expr_codes;
        for my $expr ($expressions->@*) {
            push @expr_codes, $self->_emit_expression($expr);
        }

        my $exprs_str;
        if (scalar @expr_codes == 1) {
            $exprs_str = "[$expr_codes[0]]";
        } else {
            $exprs_str = "[\n            " . join(",\n            ", @expr_codes) . ",\n        ]";
        }

        return "        push \@rules, Chalk::Grammar::Rule->new(\n"
             . "            name => '" . $self->_escape_single_quote($name) . "',\n"
             . "            expressions => $exprs_str,\n"
             . "        );\n";
    }

    # Escape a string for embedding in a single-quoted Perl string literal
    method _escape_single_quote($str) {
        $str =~ s/\\/\\\\/g;   # \ -> \\
        $str =~ s/'/\\'/g;     # ' -> \'
        return $str;
    }

    method generate_distribution($ir) {
        return {
            'lib/Chalk/Grammar/BNF/Generated.pm' => $self->generate($ir),
        };
    }

    method _postamble() {
        return q[        return \@rules;
    }
}
];
    }
}
