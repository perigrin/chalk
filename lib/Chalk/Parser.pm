# ABOUTME: Earley parser implementation with Leo optimization for Chalk
# ABOUTME: Provides EarleyItem, LeoItem, EarleyChart, and Parser classes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Semiring::SPPF;

class Chalk::EarleyItem {
    use overload '""' => 'key';

    field $start_pos :param :reader;
    field $rule      :param :reader;
    field $dot_pos   :param :reader;
    field $end_pos   :param :reader;
    field $rule_id = $rule->id;
    field @rhs     = $rule->rhs->@*;
    field $complete    :reader = $dot_pos >= scalar(@rhs);
    field $next_symbol :reader = $complete ? '' : $rhs[$dot_pos];
    field $key = "Earley|$start_pos|$rule_id|$dot_pos|$end_pos";

    method advance_dot() {
        Chalk::EarleyItem->new(
            start_pos => $start_pos,
            rule      => $rule,
            dot_pos   => $dot_pos + 1,
            end_pos   => $end_pos,
        );
    }

    method key(@) { $key }
}

class Chalk::LeoItem {
    use overload '""' => 'key';

    field $symbol    :param :reader;
    field $start_pos :param :reader;
    field $end_pos   :param :reader;
    field $top_item  :param :reader;
    field $rule      :reader = $top_item->rule;

    method complete()    { 1 }
    method next_symbol() { }

    method key(@) {
        return "LEO:$symbol|$start_pos|$end_pos";
    }

}

class Chalk::EarleyChart {
    field $semiring :param;
    field %chart;
    field @by_end_pos;
    field %predicted;    # Track what we've predicted at each position
    field %completed;    # Track what we've completed

    method add_item($earley_item) {
        $chart{ $earley_item->key } = $earley_item;
    }

    method get_element($key) { $chart{$key} }

    method add_element( $item, $element ) {
        my $key     = $item->key;
        my $current = $self->get_element($key);
        $chart{$key} = $current ? $current + $element : $element;

        push( $by_end_pos[ $item->end_pos ]->@*, $item );

        return $chart{$key};
    }

    method items_ending_at($end_pos) {
        return $by_end_pos[$end_pos]->@* if $by_end_pos[$end_pos];
        return;
    }

    method has_item($item) {
        return exists( $chart{$item} );
    }

    method has_predicted( $nonterminal, $pos, $rule_id ) {
        return exists( $predicted{"$nonterminal|$pos|$rule_id"} );
    }

    method mark_predicted( $nonterminal, $pos, $rule_id ) {
        $predicted{"$nonterminal|$pos|$rule_id"} = 1;
    }

    method has_completed($item) {
        return exists( $completed{$item} );
    }

    method mark_completed($item) {
        $completed{$item} = 1;
    }

    method goal_value( $start_symbol, $n ) {

        # Find all complete items that span [0,n] with LHS = start_symbol
        my $result = $semiring->add_id;

        my @items = $self->items_ending_at($n);

        for my $item (@items) {
            next unless $item->complete;
            next unless $item->start_pos == 0;
            next unless $item->rule->lhs eq $start_symbol;

            my $element = $self->get_element($item);
            if ($element) {
                $result = $result + $element;
            }
        }

        # Check if we found any valid parses
        return $result == $semiring->add_id ? undef : $result;
    }
}

class Chalk::Parser {
    field $semiring :param = Chalk::Semiring::SPPFViterbiSemiring->new();
    field $grammar :param;

    method parse_string($input_string) {
        my $chart = Chalk::EarleyChart->new( semiring => $semiring );

       # Initialize chart by predicting all rules for start symbol at position 0
        my $start_symbol = $grammar->start_symbol;
        for my $rule ( $grammar->rules_for($start_symbol) ) {
            my $start_item = Chalk::EarleyItem->new(
                start_pos => 0,
                rule      => $rule,
                dot_pos   => 0,
                end_pos   => 0,
            );

            my $start_element = $semiring->init_element_from_rule($rule, 0, 0);
            $chart->add_element( $start_item, $start_element );
        }

        # Process positions from 0 to end of string
        my $pos             = 0;
        my $input_length    = length($input_string);
        my $last_active_pos = 0;

        while ( $pos <= $input_length ) {
            my @agenda_before = $chart->items_ending_at($pos);
            $self->process_position_string( $pos, $chart, $input_string );

            # Track the last position where we had active items
            if ( @agenda_before > 0 ) {
                $last_active_pos = $pos;
            }

            ++$pos;
        }

        my $result =
          $chart->goal_value( $grammar->start_symbol, $input_length );

        # Show where parsing actually stopped if it failed
        if ( !$result && $last_active_pos < $input_length ) {
            warn(
"🔍 PARSING STOPPED: Reached position $last_active_pos of $input_length ("
                  . sprintf( "%.1f", 100 * $last_active_pos / $input_length )
                  . "%)\n" );
        }

        return $result;
    }

    method process_position_string( $pos, $chart, $input_string ) {
        my @agenda = $chart->items_ending_at($pos);

        while ( my $item = shift(@agenda) ) {
            my $element = $chart->get_element($item);
            next unless defined($element);

            if ( $item->complete ) {
                $self->complete( $item, $element, $chart, \@agenda );
            }
            elsif ( defined( my $next_sym = $item->next_symbol ) ) {
                if ( $grammar->is_nonterminal($next_sym) ) {
                    $self->predict( $item, $next_sym, $chart, \@agenda );
                }
                else {
                    # Try to match terminal with lexeme support
                    my $pattern = $item->rule->terminal_to_regex($next_sym);
                    pos($input_string) = $pos;
                    if ( $input_string =~ /\G($pattern)/gc ) {
                        my $match_length = length($1);
                        $self->scan( $item, $element, $chart, $pos,
                            $match_length );
                    }
                }
            }
        }
    }

    method complete( $completed_item, $completed_element, $chart, $agenda ) {

        # Check if we've already completed this item
        return if $chart->has_completed($completed_item);
        $chart->mark_completed($completed_item);

        my $lhs = $completed_item->rule->lhs;

        my @waiting = $chart->items_ending_at( $completed_item->start_pos );

        # Separate Leo items from regular items
        my @leo_waiting =
          grep { $_ isa Chalk::LeoItem && $_->symbol eq $lhs } @waiting;
        my @regular_waiting =
          grep { !( $_ isa Chalk::LeoItem ) && !$_->complete } @waiting;

        my @waiting_for_lhs = grep { $_->next_symbol eq $lhs } @regular_waiting;

  # Check for deterministic reduction (only if no Leo items waiting)
  # Leo items are only for deterministic right-recursive chains where:
  # 1. Only one item is waiting for this LHS
  # 2. The waiting item will be complete after this reduction
  # 3. The rule is right-recursive
  #
  # NOTE: Joop Leo's second optimization for left-recursion could be implemented
  # here, but performance testing shows left-recursion is already faster than
  # right-recursion in our Earley implementation, so it's not needed.
        if (   @waiting_for_lhs == 1
            && @leo_waiting == 0
            && $waiting_for_lhs[0]->rule->is_right_recursive
            && $waiting_for_lhs[0]->dot_pos ==
            scalar( $waiting_for_lhs[0]->rule->rhs->@* ) - 1 )
        {
            my $waiting_item = $waiting_for_lhs[0];

            # Use completed item's end position
            my $leo = Chalk::LeoItem->new(
                symbol    => $lhs,
                start_pos => $waiting_item->start_pos,
                end_pos   => $completed_item->end_pos,
                top_item  => $waiting_item,
            );

            my $waiting_element = $chart->get_element($waiting_item);
            next unless $waiting_element;
            my $combined_element = $waiting_element * $completed_element;
            $chart->add_element( $leo, $combined_element );
            push( @$agenda, $leo );
            return;    # Skip normal completion
        }

        # Normal completion for regular items
        for my $waiting_item (@waiting_for_lhs) {

            my $waiting_element = $chart->get_element($waiting_item);
            next unless $waiting_element;

            # Semiring multiplication ⊗ combines sequential components
            my $combined_element = $waiting_element * $completed_element;

            my $new_item = Chalk::EarleyItem->new(
                start_pos => $waiting_item->start_pos,
                rule      => $waiting_item->rule,
                dot_pos   => $waiting_item->dot_pos + 1,
                end_pos   => $completed_item->end_pos
            );

            # Only add if not already in chart
            unless ( $chart->has_item($new_item) ) {
                $chart->add_element( $new_item, $combined_element );
                push( @$agenda, $new_item );
            }
        }

        # Handle Leo items waiting for this completion
        for my $leo_item (@leo_waiting) {

            # Unpack the Leo chain to get the original waiting item
            my $current = $leo_item->top_item;
            while ( $current isa Chalk::LeoItem ) {
                $current = $current->top_item;
            }

            # Now $current is the original EarleyItem at the bottom of the chain
            # Complete it with the current completed item
            my $waiting_element = $chart->get_element($leo_item);
            next unless $waiting_element;
            my $combined_element = $waiting_element * $completed_element;

            my $new_item = Chalk::EarleyItem->new(
                start_pos => $current->start_pos,
                rule      => $current->rule,
                dot_pos   => $current->dot_pos + 1,
                end_pos   => $completed_item->end_pos
            );

            # Only add if not already in chart
            unless ( $chart->has_item($new_item) ) {
                $chart->add_element( $new_item, $combined_element );
                push( @$agenda, $new_item );
            }
        }
    }

    method predict( $item, $nonterminal, $chart, $agenda ) {
        my $pos = $item->end_pos;

# Check if we've already predicted this nonterminal from this rule at this position
# Multiple rules can predict the same nonterminal, so we track by rule origin
        return if $chart->has_predicted( $nonterminal, $pos, $item->rule->id );
        $chart->mark_predicted( $nonterminal, $pos, $item->rule->id );

        for my $rule ( $grammar->rules_for($nonterminal) ) {
            my $predicted_item = Chalk::EarleyItem->new(
                start_pos => $pos,
                rule      => $rule,
                dot_pos   => 0,
                end_pos   => $pos
            );

            # Only add if not already in chart
            unless ( $chart->has_item($predicted_item) ) {
                my $rule_element = $semiring->init_element_from_rule($rule, $pos, $pos);
                $chart->add_element( $predicted_item, $rule_element );
                push( @$agenda, $predicted_item );
            }
        }

        # Aycock-Horspool optimization: if the nonterminal is nullable,
        # we can also advance the dot past it immediately
        if ( $grammar->is_nullable($nonterminal) ) {
            my $advanced_item = Chalk::EarleyItem->new(
                start_pos => $item->start_pos,
                rule      => $item->rule,
                dot_pos   => $item->dot_pos + 1,
                end_pos   => $item->end_pos
            );

            # Only add if not already present
            unless ( $chart->has_item($advanced_item) ) {
                my $current_element = $chart->get_element($item);
                if ($current_element) {
                    $chart->add_element( $advanced_item, $current_element );
                    push( @$agenda, $advanced_item );
                }
            }
        }
    }

    method scan( $item, $element, $chart, $pos, $match_length ) {
        my $scanned_item = Chalk::EarleyItem->new(
            start_pos => $item->start_pos,
            rule      => $item->rule,
            dot_pos   => $item->dot_pos + 1,
            end_pos   => $pos + $match_length
        );

        # All semirings receive position updates during scan
        # Semirings can choose to use or ignore positions based on their needs
        my $scanned_element = $semiring->init_element_from_rule(
            $item->rule,
            $scanned_item->start_pos,
            $scanned_item->end_pos
        );

        $chart->add_element( $scanned_item, $scanned_element );
    }
}

1;
