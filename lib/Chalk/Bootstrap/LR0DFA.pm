# ABOUTME: LR(0) DFA construction from grammar for Aycock prediction optimization.
# ABOUTME: Pre-clusters predicted items into states for O(1) prediction lookup per nonterminal.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::LR0DFA {
    field $grammar    :param :reader;  # arrayref of Rule objects
    field $core_index :param :reader;  # CoreItemIndex
    field $rule_table :param :reader;  # { rule_name => Rule }

    # Prediction cache: { nonterminal_name => [[$core_id, $skip_symbols], ...] }
    # Each entry is the set of core items reachable by transitively predicting
    # nonterminals. Includes dot>0 items for nullable symbol advancement.
    # $skip_symbols is an arrayref of ?-quantified symbol names skipped to reach
    # this dot position (empty arrayref for dot=0 items).
    field %prediction_items;

    # Nullable set: { nonterminal_name => true } for nonterminals that can
    # derive the empty string. Computed via fixed-point iteration.
    field %nullable;

    # State count for reporting
    field $state_count :reader = 0;

    # Build the DFA prediction tables from the grammar.
    # First computes the nullable set, then for each nonterminal computes the
    # epsilon-closure including dot-advanced items past nullable symbols.
    method build() {
        $self->_compute_nullable_set();

        # For each nonterminal, compute prediction items via epsilon-closure
        for my $rule ($grammar->@*) {
            my $name = $rule->name();
            next if exists $prediction_items{$name};
            $self->_compute_prediction_closure($name);
        }
        # Count unique states (one per nonterminal prediction set)
        $state_count = scalar keys %prediction_items;
    }

    # Compute the set of nullable nonterminals using fixed-point iteration.
    # A nonterminal N is nullable if any of its alternatives:
    #   - Is empty (epsilon production), OR
    #   - Has all symbols being nullable (nonterminal + nullable, or ?-quantified)
    method _compute_nullable_set() {
        # Seed: find all nonterminals with empty alternatives
        my $changed = true;
        for my $rule ($grammar->@*) {
            for my $alt ($rule->expressions()->@*) {
                if (scalar $alt->@* == 0) {
                    $nullable{$rule->name()} = true;
                }
            }
        }

        # Fixed-point: iterate until no new nullables found
        while ($changed) {
            $changed = false;
            for my $rule ($grammar->@*) {
                my $name = $rule->name();
                next if $nullable{$name};
                for my $alt ($rule->expressions()->@*) {
                    my $all_nullable = true;
                    for my $sym ($alt->@*) {
                        if ($sym->is_quantified() && $sym->quantifier() eq '?') {
                            # ?-quantified symbols are inherently nullable
                            next;
                        }
                        if ($sym->is_reference() && $nullable{$sym->value()}) {
                            # Nullable nonterminal reference
                            next;
                        }
                        # Non-nullable symbol found
                        $all_nullable = false;
                        last;
                    }
                    if ($all_nullable && scalar $alt->@* > 0) {
                        $nullable{$name} = true;
                        $changed = true;
                    }
                }
            }
        }
    }

    # Check if a nonterminal is nullable.
    method is_nullable($nonterminal) {
        return $nullable{$nonterminal} ? true : false;
    }

    # Compute the epsilon-closure for a nonterminal: all core items
    # reachable by transitively following nonterminal references.
    # Includes dot-advanced items past nullable symbols (Aycock optimization).
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
                push @result, [$core_id, []] if defined $core_id;

                # Advance through consecutive nullable symbols at the start
                # of this alternative, adding dot-advanced items.
                my $alt = $expressions->[$alt_idx];
                my $dot = 0;
                my @skipped;  # Track ?-quantified symbol names skipped
                while ($dot < scalar $alt->@*) {
                    my $sym = $alt->[$dot];
                    last unless $sym->is_reference();
                    my $ref_name = $sym->value();
                    push @worklist, $ref_name unless $visited{$ref_name};

                    # Is this symbol nullable (can be skipped)?
                    my $is_nullable_sym = ($sym->is_quantified() && $sym->quantifier() eq '?')
                                       || $nullable{$ref_name};
                    if ($is_nullable_sym) {
                        # Track ?-quantified skips for on_skip_optional placeholders
                        my @skip_copy = @skipped;
                        if ($sym->is_quantified() && $sym->quantifier() eq '?') {
                            push @skip_copy, $ref_name;
                        }
                        # Add dot-advanced core item
                        my $adv_id = $core_index->id_for($nt, $alt_idx, $dot + 1);
                        push @result, [$adv_id, \@skip_copy] if defined $adv_id;
                        # Update running skip list for further advancement
                        if ($sym->is_quantified() && $sym->quantifier() eq '?') {
                            push @skipped, $ref_name;
                        }
                        $dot++;
                    } else {
                        last;
                    }
                }
            }
        }

        $prediction_items{$nonterminal} = \@result;
    }

    # Get the prediction items for a nonterminal: core items
    # reachable via epsilon-closure, including dot-advanced items.
    # Returns arrayref of [$core_id, $skip_symbols] pairs.
    method prediction_items_for($nonterminal) {
        return $prediction_items{$nonterminal};
    }
}
