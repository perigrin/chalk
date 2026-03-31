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

        return {
            'dfa_tables.c' => "/* stub */\n",
            'dfa_tables.h' => "/* stub */\n",
        };
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
