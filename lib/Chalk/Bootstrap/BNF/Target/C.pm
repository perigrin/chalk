# ABOUTME: C code generation target that reconstructs grammar from BNF IR and builds LR0DFA.
# ABOUTME: Returns stub C file content; serialization of static DFA tables is done in later phases.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::CoreItemIndex;
use Chalk::Bootstrap::LR0DFA;

class Chalk::Bootstrap::BNF::Target::C :isa(Chalk::Bootstrap::Target) {

    # Lexical helpers used by _emit_core_item_arrays().
    # Defined as my subs so they are resolved at compile time within the class scope.

    # Escape a Perl string for use as a C string literal and wrap it in double quotes.
    my sub _c_string($s) {
        $s =~ s/\\/\\\\/g;
        $s =~ s/"/\\"/g;
        return qq("$s");
    }

    # Emit a single static C array declaration with the given type, name, size, and values.
    # Values must already be formatted as C literal strings (e.g. via _c_string, or plain ints).
    my sub _emit_c_array($type, $name, $n, $values) {
        my $init = join(', ', $values->@*);
        return "static $type $name\[$n\] = { $init };\n";
    }

    # Stored after the most recent generate() call for introspection by tests
    # and for use by future serialization methods.
    field $last_dfa_state_count :reader = 0;
    field $last_terminal_patterns :reader = [];
    field $last_rule_count :reader = 0;

    # Fields holding the built objects for use by future serialization phases.
    field $core_index;
    field $lr0_dfa;
    field $grammar;

    # Generate stub C output from an arrayref of Constructor:Rule IR nodes.
    # Reconstructs Rule/Symbol objects, builds CoreItemIndex and LR0DFA,
    # stores them for later serialization, and returns stub file content.
    method generate($ir) {
        die "generate() requires an arrayref of IR rules"
            unless defined($ir) && ref($ir) eq 'ARRAY';

        # Reset stored state so each call is independent
        $last_dfa_state_count = 0;
        $last_terminal_patterns = [];
        $last_rule_count = 0;
        $core_index = undef;
        $lr0_dfa    = undef;
        $grammar    = undef;

        # Reconstruct Rule/Symbol objects from the IR
        my @rules = $self->_reconstruct_rules($ir);
        $last_rule_count = scalar @rules;

        # Collect all terminal patterns for introspection
        my @patterns;
        for my $rule (@rules) {
            for my $alt ($rule->expressions()->@*) {
                for my $sym ($alt->@*) {
                    push @patterns, $sym->value()
                        if $sym->type() eq 'terminal';
                }
            }
        }
        $last_terminal_patterns = \@patterns;

        # Build CoreItemIndex and LR0DFA when there are rules to process
        if (@rules) {
            my $index = Chalk::Bootstrap::CoreItemIndex->new();
            $index->build_from_grammar(\@rules);

            my %rule_table = map { $_->name() => $_ } @rules;
            my $dfa = Chalk::Bootstrap::LR0DFA->new(
                grammar    => \@rules,
                core_index => $index,
                rule_table => \%rule_table,
            );
            $dfa->build();

            $core_index           = $index;
            $lr0_dfa              = $dfa;
            $grammar              = \@rules;
            $last_dfa_state_count = $dfa->state_count();
        }

        my $c_body = "/* stub */\n";
        $c_body = $self->_emit_core_item_arrays() if $core_index;

        return {
            'dfa_tables.c' => $c_body,
            'dfa_tables.h' => "/* stub */\n",
        };
    }

    # Emit the 7 CoreItemIndex parallel arrays as static C source.
    # All arrays are indexed by core_id (0 to count-1).
    method _emit_core_item_arrays() {
        my $n = $core_index->count();

        # Collect per-id values up front.
        my @rule_names;
        my @alt_idxs;
        my @dots;
        my @is_complete;
        my @advance;
        my @to_state;
        my @sym_patterns;
        my @sym_is_ref;

        for my $id (0 .. $n - 1) {
            push @rule_names,   _c_string($core_index->rule_name_for($id));
            push @alt_idxs,     $core_index->alt_idx_for($id);
            push @dots,         $core_index->dot_for($id);

            my $complete = $core_index->is_complete($id) ? 1 : 0;
            push @is_complete, $complete;

            my $adv = $core_index->advance($id);
            push @advance, defined($adv) ? $adv : -1;

            my $state = $core_index->state_for($id);
            push @to_state, defined($state) ? $state : -1;

            my $sym = $core_index->symbol_after($id);
            if (defined $sym) {
                push @sym_patterns, _c_string($sym->value());
                push @sym_is_ref,   $sym->is_reference() ? 1 : 0;
            }
            else {
                push @sym_patterns, 'NULL';
                push @sym_is_ref,   0;
            }
        }

        my $out = '';

        $out .= "#define NUM_CORE_ITEMS $n\n\n";

        $out .= _emit_c_array('const char *', 'ci_rule_names',          $n, \@rule_names);
        $out .= _emit_c_array('const int',    'ci_alt_idxs',            $n, \@alt_idxs);
        $out .= _emit_c_array('const int',    'ci_dots',                $n, \@dots);
        $out .= _emit_c_array('const int',    'ci_is_complete',         $n, \@is_complete);
        $out .= _emit_c_array('const int',    'ci_advance',             $n, \@advance);
        $out .= _emit_c_array('const int',    'ci_to_state',            $n, \@to_state);
        $out .= _emit_c_array('const char *', 'ci_symbol_after_pattern',$n, \@sym_patterns);
        $out .= _emit_c_array('const int',    'ci_symbol_after_is_ref', $n, \@sym_is_ref);

        return $out;
    }

    # generate_distribution wraps generate() with the standard distribution shape.
    method generate_distribution($ir) {
        return $self->generate($ir);
    }

    # Reconstruct Chalk::Grammar::Rule and Chalk::Grammar::Symbol objects
    # from an arrayref of Constructor:Rule IR nodes.
    method _reconstruct_rules($ir) {
        my @rules;
        for my $rule_node ($ir->@*) {
            push @rules, $self->_reconstruct_rule($rule_node);
        }
        return @rules;
    }

    # Reconstruct a single Chalk::Grammar::Rule from a Constructor:Rule IR node.
    # IR layout: inputs()->[0] = Constant(name), inputs()->[1] = arrayref of Expression nodes
    method _reconstruct_rule($rule_node) {
        my $inputs      = $rule_node->inputs();
        my $name        = $inputs->[0]->value();
        my $expr_nodes  = $inputs->[1];

        my @expressions;
        for my $expr_node ($expr_nodes->@*) {
            push @expressions, $self->_reconstruct_expression($expr_node);
        }

        return Chalk::Grammar::Rule->new(
            name        => $name,
            expressions => \@expressions,
        );
    }

    # Reconstruct a single alternative (arrayref of Symbol objects)
    # from a Constructor:Expression IR node.
    # IR layout: inputs()->[0] = arrayref of Symbol Constructor nodes
    method _reconstruct_expression($expr_node) {
        my $symbol_nodes = $expr_node->inputs()->[0];
        my @symbols;
        for my $sym_node ($symbol_nodes->@*) {
            push @symbols, $self->_reconstruct_symbol($sym_node);
        }
        return \@symbols;
    }

    # Reconstruct a single Chalk::Grammar::Symbol from a Constructor:Symbol IR node.
    # IR layout: inputs()->[0] = Constant(type), inputs()->[1] = Constant(value),
    #            inputs()->[2] = Constant(quantifier) or undef
    method _reconstruct_symbol($sym_node) {
        my $inputs     = $sym_node->inputs();
        my $type_str   = $inputs->[0]->value();
        my $raw_value  = $inputs->[1]->value();
        my $quant_node = $inputs->[2];
        my $quant_str  = defined($quant_node) ? $quant_node->value() : undef;

        # Strip /…/ delimiters from terminal values (same logic as Target::Perl)
        my $value = $raw_value;
        if ($type_str eq 'terminal' && $value =~ m{^/(.*)/$}s) {
            $value = $1;
        }

        my %args = (type => $type_str, value => $value);
        $args{quantifier} = $quant_str if defined $quant_str;

        return Chalk::Grammar::Symbol->new(%args);
    }
}
