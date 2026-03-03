# ABOUTME: LR(0) DFA construction from grammar for Aycock prediction optimization.
# ABOUTME: Pre-clusters predicted items into states for O(1) prediction lookup per nonterminal.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::LR0DFA {
    field $grammar    :param :reader;  # arrayref of Rule objects
    field $core_index :param :reader;  # CoreItemIndex
    field $rule_table :param :reader;  # { rule_name => Rule }

    # Prediction cache: { nonterminal_name => [core_id, ...] }
    # Each entry is the set of core items at dot=0 for all alternatives
    # of that nonterminal, plus all transitively predicted nonterminals.
    field %prediction_items;

    # State count for reporting
    field $state_count :reader = 0;

    # Build the DFA prediction tables from the grammar.
    # For each nonterminal, compute the epsilon-closure: all core items
    # at dot=0 that are reachable by transitively predicting nonterminals.
    method build() {
        # For each nonterminal, compute prediction items via epsilon-closure
        for my $rule ($grammar->@*) {
            my $name = $rule->name();
            next if exists $prediction_items{$name};
            $self->_compute_prediction_closure($name);
        }
        # Count unique states (one per nonterminal prediction set)
        $state_count = scalar keys %prediction_items;
    }

    # Compute the epsilon-closure for a nonterminal: all (rule, alt, dot=0)
    # core items reachable by transitively following nonterminal references.
    method _compute_prediction_closure($nonterminal) {
        my @result;
        my %visited;  # nonterminals already expanded
        my @worklist = ($nonterminal);

        while (my $nt = shift @worklist) {
            next if $visited{$nt}++;
            my $rule = $rule_table->{$nt};
            next unless defined $rule;

            my $expressions = $rule->expressions();
            for my $alt_idx (0 .. $expressions->$#*) {
                # Add core item at dot=0 for this alternative
                my $core_id = $core_index->id_for($nt, $alt_idx, 0);
                push @result, $core_id if defined $core_id;

                # If the first symbol(s) of this alternative are nonterminals,
                # transitively predict them. When a symbol is X?, the next
                # symbol also needs prediction (X? can be skipped).
                my $alt = $expressions->[$alt_idx];
                my $dot = 0;
                while ($dot < scalar $alt->@*) {
                    my $sym = $alt->[$dot];
                    last unless $sym->is_reference();
                    my $ref_name = $sym->value();
                    push @worklist, $ref_name unless $visited{$ref_name};
                    # Only look past optional symbols
                    last unless $sym->is_quantified() && $sym->quantifier() eq '?';
                    $dot++;
                }
            }
        }

        $prediction_items{$nonterminal} = \@result;
    }

    # Get the prediction items for a nonterminal: all core items at dot=0
    # reachable via epsilon-closure from that nonterminal.
    method prediction_items_for($nonterminal) {
        return $prediction_items{$nonterminal};
    }
}
