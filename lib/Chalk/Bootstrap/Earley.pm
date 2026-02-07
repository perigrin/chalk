# ABOUTME: Scanless Earley parser with Predict/Scan/Complete operations.
# ABOUTME: Takes grammar and semiring, returns boolean acceptance for input strings.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Terminal;

class Chalk::Bootstrap::Earley {
    field $grammar  :param :reader;
    field $semiring :param :reader;

    # Build a lookup table for rules by name
    field $rule_table;

    ADJUST {
        $rule_table = {};
        for my $rule ($grammar->@*) {
            $rule_table->{$rule->name()} = $rule;
        }
    }

    # Earley item: [rule, dot_position, origin, semiring_value]
    # We use hashrefs for items to make debugging easier
    method _make_item($rule, $dot, $origin, $value) {
        return {
            rule   => $rule,
            dot    => $dot,
            origin => $origin,
            value  => $value,
        };
    }

    # Get the symbol after the dot in an item
    method _symbol_after_dot($item, $alt_index) {
        my $rule = $item->{rule};
        my $dot = $item->{dot};
        my $alt = $rule->expressions()->[$alt_index];

        return undef if $dot >= scalar $alt->@*;
        return $alt->[$dot];
    }

    # Check if item is complete (dot at end)
    method _is_complete($item, $alt_index) {
        my $rule = $item->{rule};
        my $dot = $item->{dot};
        my $alt = $rule->expressions()->[$alt_index];

        return $dot >= scalar $alt->@*;
    }

    # Internal parse implementation that returns raw semiring value or undef
    method _run_parse($input) {
        my $n = length($input);

        # Chart: array of sets, where each set is a hash of items
        # Key format: "rule_name:alt_index:dot:origin"
        my @chart = map { {} } (0 .. $n);

        # Find the start rule (first rule in grammar)
        my $start_rule = $grammar->[0];

        # Initialize chart[0] with start rule items (one per alternative)
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $item = $self->_make_item($start_rule, 0, 0, $semiring->one());
            my $key = $self->_item_key($item, $alt_idx);
            $chart[0]->{$key} = [$item, $alt_idx];
        }

        # Process each chart position
        for my $pos (0 .. $n) {
            my $agenda = [values $chart[$pos]->%*];
            my $processed = {};

            while (my $entry = shift $agenda->@*) {
                my ($item, $alt_idx) = $entry->@*;
                my $key = $self->_item_key($item, $alt_idx);

                # Skip if already processed
                next if $processed->{$key};
                $processed->{$key} = true;

                if ($self->_is_complete($item, $alt_idx)) {
                    # Apply semantic action for completed rule before propagating
                    if ($semiring->can('complete_value')) {
                        $item = { %$item, value => $semiring->complete_value($item->{value}, $item->{rule}->name()) };
                        # Update the chart entry with the action-applied value
                        $chart[$pos]->{$key} = [$item, $alt_idx];
                    }
                    # Complete
                    $self->_complete($item, $alt_idx, $pos, \@chart, $agenda);
                } else {
                    my $symbol = $self->_symbol_after_dot($item, $alt_idx);

                    if ($symbol->is_reference()) {
                        # Predict
                        $self->_predict($symbol, $pos, \@chart, $agenda);
                    } else {
                        # Scan (allow at end of input for zero-width matches)
                        $self->_scan($item, $alt_idx, $symbol, $pos, $input, \@chart, $agenda, $n);
                    }
                }
            }
        }

        # Check if we have a completed start rule spanning entire input
        for my $alt_idx (0 .. $start_rule->expressions()->$#*) {
            my $key = $self->_item_key(
                $self->_make_item($start_rule, scalar($start_rule->expressions()->[$alt_idx]->@*), 0, undef),
                $alt_idx
            );

            if (exists $chart[$n]->{$key}) {
                my $item = $chart[$n]->{$key}->[0];
                return $item->{value};
            }
        }

        return undef;
    }

    # Parse input string, returns boolean indicating success
    method parse($input) {
        my $value = $self->_run_parse($input);
        return defined($value) ? !$semiring->is_zero($value) : false;
    }

    # Parse input string, returns raw semiring value (or undef on failure)
    method parse_value($input) {
        return $self->_run_parse($input);
    }

    # Predict: add items for all alternatives of a nonterminal
    method _predict($symbol, $pos, $chart, $agenda) {
        my $rule_name = $symbol->value();
        my $rule = $rule_table->{$rule_name};

        return unless defined $rule;

        for my $alt_idx (0 .. $rule->expressions()->$#*) {
            my $item = $self->_make_item($rule, 0, $pos, $semiring->one());
            my $key = $self->_item_key($item, $alt_idx);

            unless (exists $chart->[$pos]->{$key}) {
                $chart->[$pos]->{$key} = [$item, $alt_idx];
                push $agenda->@*, [$item, $alt_idx];
            }
        }
    }

    # Scan: match terminal and advance to next position
    method _scan($item, $alt_idx, $symbol, $pos, $input, $chart, $agenda, $n) {
        my $pattern_str = $symbol->value();
        my $pattern = qr/$pattern_str/;
        my $end_pos = Chalk::Bootstrap::Terminal::match($input, $pos, $pattern);

        return unless defined $end_pos;

        # Capture matched text and create scan value
        my $matched = substr($input, $pos, $end_pos - $pos);
        my $scan_val = $semiring->can('scan_value')
            ? $semiring->scan_value($matched)
            : $semiring->one();

        # Advance dot
        my $new_item = $self->_make_item(
            $item->{rule},
            $item->{dot} + 1,
            $item->{origin},
            $semiring->multiply($item->{value}, $scan_val)
        );

        my $key = $self->_item_key($new_item, $alt_idx);

        if (exists $chart->[$end_pos]->{$key}) {
            # Merge with existing item using semiring add (create new item, don't mutate)
            my $existing = $chart->[$end_pos]->{$key}->[0];
            my $merged_value = $semiring->add($existing->{value}, $new_item->{value});
            my $merged_item = $self->_make_item(
                $existing->{rule},
                $existing->{dot},
                $existing->{origin},
                $merged_value,
            );
            $chart->[$end_pos]->{$key} = [$merged_item, $alt_idx];
            # If zero-width match, add to current agenda for immediate processing
            # (The $processed hash prevents infinite loops from repeated zero-width matches)
            if ($end_pos == $pos) {
                push $agenda->@*, [$merged_item, $alt_idx];
            }
        } else {
            $chart->[$end_pos]->{$key} = [$new_item, $alt_idx];
            # If zero-width match, add to current agenda for immediate processing
            # (The $processed hash prevents infinite loops from repeated zero-width matches)
            if ($end_pos == $pos) {
                push $agenda->@*, [$new_item, $alt_idx];
            }
        }
    }

    # Complete: combine completed items with items waiting for them
    method _complete($completed_item, $completed_alt_idx, $pos, $chart, $agenda) {
        my $rule_name = $completed_item->{rule}->name();
        my $origin = $completed_item->{origin};

        # Find all items at origin position that are waiting for this rule
        for my $key (keys $chart->[$origin]->%*) {
            my ($waiting_item, $waiting_alt_idx) = $chart->[$origin]->{$key}->@*;

            next if $self->_is_complete($waiting_item, $waiting_alt_idx);

            my $symbol = $self->_symbol_after_dot($waiting_item, $waiting_alt_idx);
            next unless $symbol && $symbol->is_reference();
            next unless $symbol->value() eq $rule_name;

            # Advance the waiting item
            my $new_item = $self->_make_item(
                $waiting_item->{rule},
                $waiting_item->{dot} + 1,
                $waiting_item->{origin},
                $semiring->multiply($waiting_item->{value}, $completed_item->{value})
            );

            my $new_key = $self->_item_key($new_item, $waiting_alt_idx);

            if (exists $chart->[$pos]->{$new_key}) {
                # Merge with existing item using semiring add (create new item, don't mutate)
                my $existing = $chart->[$pos]->{$new_key}->[0];
                my $merged_value = $semiring->add($existing->{value}, $new_item->{value});
                my $merged_item = $self->_make_item(
                    $existing->{rule},
                    $existing->{dot},
                    $existing->{origin},
                    $merged_value,
                );
                $chart->[$pos]->{$new_key} = [$merged_item, $waiting_alt_idx];
            } else {
                $chart->[$pos]->{$new_key} = [$new_item, $waiting_alt_idx];
                push $agenda->@*, [$new_item, $waiting_alt_idx];
            }
        }
    }

    # Generate unique key for item
    method _item_key($item, $alt_idx) {
        return join(':', $item->{rule}->name(), $alt_idx, $item->{dot}, $item->{origin});
    }
}
