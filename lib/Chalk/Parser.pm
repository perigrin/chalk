# ABOUTME: Earley parser implementation with Leo optimization for Chalk
# ABOUTME: Provides EarleyItem, LeoItem, EarleyChart, and Parser classes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Semiring::Boolean;
use Chalk::Grammar::Token;
use Chalk::Preprocessor::Heredoc;

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

    method key(@args) { $key }
}

# Leo Items: Limited optimization for right-recursive grammar patterns
#
# This is a LIMITED implementation of Joop Leo's optimization (1991) for right-recursive
# grammars.  It creates "Leo items" only in DETERMINISTIC cases where:
# 1. Exactly one Earley item is waiting for the completed symbol
# 2. The waiting item will be complete after this one reduction
# 3. The rule is right-recursive (LHS appears as last RHS symbol)
#
# Why limited? Full Leo would create items even with multiple waiting items and maintain
# a hash lookup by (position, symbol). Our grammar has 41 right-recursive rules, but
# performance testing shows grammar complexity (960+ rules) is the main bottleneck,
# not right-recursion specifically. This limited implementation provides O(n) behavior
# for simple right-recursive chains (ArrowChain, StatementList) without the complexity
# of full Leo.
#
# See t/optimization/test-leo-items.t for verification tests.
# See issue #10 for detailed analysis and rationale.
class Chalk::LeoItem {
    use overload '""' => 'key';

    field $symbol    :param :reader;
    field $start_pos :param :reader;
    field $end_pos   :param :reader;
    field $top_item  :param :reader;
    field $rule      :reader = $top_item->rule;

    method complete()    { 1 }
    method next_symbol() { }
    method dot_pos()     { scalar( $rule->rhs ) } # LeoItems are always complete

    method key(@args) {
        return "LEO:$symbol|$start_pos|$end_pos";
    }

}

class Chalk::EarleyChart {
    field $semiring :param;
    field %chart;
    field @by_end_pos;
    field %predicted;    # Track what we've predicted at each position
    field %completed;    # Track what we've completed
    field %waiting_for
      ;    # Index: waiting_for{symbol}{pos} = [items waiting for symbol at pos]
    field %leo_waiting_for
      ; # Index: leo_waiting_for{symbol}{pos} = [Leo items waiting for symbol at pos]

    method add_item($earley_item) {
        $chart{ $earley_item->key } = $earley_item;
    }

    method get_element($key) { $chart{$key} }

    # Merge element via semiring add() without re-indexing (for existing items)
    method merge_element( $item, $element ) {
        my $key     = $item->key;
        my $current = $self->get_element($key);
        $chart{$key} = $current ? $current + $element : $element;
        return $chart{$key};
    }

    method add_element( $item, $element ) {
        my $key     = $item->key;
        my $current = $self->get_element($key);
        $chart{$key} = $current ? $current + $element : $element;

        my $end_pos = $item->end_pos;
        push( $by_end_pos[$end_pos]->@*, $item );

        # Index by what they're waiting for
        if ( $item isa Chalk::LeoItem ) {

            # Leo items are indexed by their symbol and end position
            my $symbol      = $item->symbol;
            my $leo_end_pos = $item->end_pos;
            $leo_waiting_for{$symbol} //= {};
            my $leo_by_symbol = $leo_waiting_for{$symbol};
            $leo_by_symbol->{$leo_end_pos} //= [];
            my $leo_list = $leo_by_symbol->{$leo_end_pos};
            push( $leo_list->@*, $item );
        }
        elsif ( !$item->complete ) {

            # Regular items indexed by next_symbol
            my $next_sym = $item->next_symbol;
            if ($next_sym) {
                my $waiting_end_pos = $item->end_pos;
                $waiting_for{$next_sym} //= {};
                my $waiting_by_sym = $waiting_for{$next_sym};
                $waiting_by_sym->{$waiting_end_pos} //= [];
                my $waiting_list = $waiting_by_sym->{$waiting_end_pos};
                push( $waiting_list->@*, $item );
            }
        }

        return $chart{$key};
    }

    method items_ending_at($end_pos) {
        return $by_end_pos[$end_pos]->@* if $by_end_pos[$end_pos];
        return;
    }

    method items_waiting_for( $symbol, $pos ) {
        my $by_symbol = $waiting_for{$symbol};
        if ( $by_symbol && exists( $by_symbol->{$pos} ) ) {
            return $by_symbol->{$pos}->@*;
        }
        return;
    }

    method leo_items_waiting_for( $symbol, $pos ) {
        my $by_symbol = $leo_waiting_for{$symbol};
        if ( $by_symbol && exists( $by_symbol->{$pos} ) ) {
            return $by_symbol->{$pos}->@*;
        }
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
                # DEBUG: Log goal elements
                if ($ENV{DEBUG_PRECEDENCE}) {
                    if ($element->can('valid')) {
                        warn "GOAL: found element valid=" . $element->valid . " op=" . ($element->operator // 'undef') . " for " . $item->rule->lhs . "\n";
                    } elsif ($element->can('elements')) {
                        my $prec = $element->elements->[0];
                        warn "GOAL: found composite element prec.valid=" . ($prec->valid // '?') . " prec.op=" . ($prec->operator // 'undef') . " for " . $item->rule->lhs . "\n";
                    }
                }
                my $old_result = $result;
                $result = $result + $element;
                if ($ENV{DEBUG_PRECEDENCE} && $result->can('valid')) {
                    warn "GOAL: after add, result.valid=" . $result->valid . " op=" . ($result->operator // 'undef') . "\n";
                }

                # Early termination for Boolean semiring: we only need to know
                # IF a parse exists, not enumerate ALL parses. This prevents
                # memory exhaustion when parsing highly ambiguous inputs like
                # the grammar file itself (which has exponentially many parses).
                # For other semirings (like Semantic), we need to accumulate ALL
                # parses to get the correct result.
                if (   $semiring isa Chalk::Semiring::Boolean
                    && $result != $semiring->add_id )
                {
                    return $result;
                }
            }
        }

        # Check if we found any valid parses
        # Return unevaluated result - let caller decide whether to evaluate
        return $result == $semiring->add_id ? undef : $result;
    }
}

class Chalk::Parser {
    field $semiring   :param = Chalk::Semiring::Boolean->new();
    field $grammar    :param;
    field $preprocess :param = [];    # Arrayref of preprocessor class names
    field $input_string;              # Store input string for semantic actions
    field @last_errors;               # Errors from last parse attempt
    field $diagnostic_context;        # Shared context for furthest-failure error tracking

    method parse_string($input) {
        $input_string = $input;       # Store for semantic actions
        @last_errors = ();            # Clear errors from previous parse

        # Initialize diagnostic context for furthest-failure error tracking
        $diagnostic_context = {
            furthest_pos => 0,
            furthest_errors => [],
            input_string => $input,
        };

        # Pass diagnostic context to semiring if it supports it
        if ($semiring->can('set_diagnostic_context')) {
            $semiring->set_diagnostic_context($diagnostic_context);
        }

        # Apply preprocessors in sequence
        for my $preprocessor_class ( $preprocess->@* ) {
            next unless defined $preprocessor_class;

            # Apply preprocessing
            my $preprocessor = $preprocessor_class->new( input => $input );
            $preprocessor->transform();
            $input = $preprocessor->output;
        }

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

            my $start_element =
              $semiring->init_element_from_rule( $rule, 0, 0 );
            $chart->add_element( $start_item, $start_element );
        }

        # Process positions from 0 to end of string
        my $pos             = 0;
        my $input_length    = length($input);
        my $last_active_pos = 0;

        # Store input_string for semantic actions
        $input_string = $input;

        # Store input_string on SPPF forest if available (for precedence validation)
        if ($semiring->can('forest') && $semiring->forest) {
            $semiring->forest->set_input_string($input);
        }
        # Handle Composite semiring wrapping SPPF
        elsif ($semiring->can('semirings')) {
            for my $child_sr ($semiring->semirings->@*) {
                if ($child_sr->can('forest') && $child_sr->forest) {
                    $child_sr->forest->set_input_string($input);
                    last;
                }
            }
        }

        while ( $pos <= $input_length ) {
            my @agenda_before = $chart->items_ending_at($pos);
            $self->process_position_string( $pos, $chart, $input );

            # Track the last position where we had active items
            if ( @agenda_before > 0 ) {
                $last_active_pos = $pos;
            }

            ++$pos;
        }

        my $result =
          $chart->goal_value( $grammar->start_symbol, $input_length );

        # Collect errors from the result if available
        if ($result) {
            $self->_collect_errors_from_element($result);
        }

        # Show where parsing actually stopped if it failed
        if ( !$result && $last_active_pos < $input_length ) {

            # Calculate line and column of failure position
            my $line_num   = 1;
            my $col        = 0;
            my $line_start = 0;
            for my $i ( 0 .. $last_active_pos - 1 ) {
                if ( substr( $input, $i, 1 ) eq "\n" ) {
                    $line_num++;
                    $line_start = $i + 1;
                    $col        = 0;
                }
                else {
                    $col++;
                }
            }

            # Extract source lines around failure position
            my @lines         = split( qr/\n/, $input, -1 );
            my $context_lines = 2;    # Show 2 lines before and after
            my $start_line    = $line_num - $context_lines - 1;
            $start_line = 0 if $start_line < 0;
            my $end_line = $line_num + $context_lines - 1;
            $end_line = $#lines if $end_line > $#lines;

            # Build context display with line numbers
            my $context = "";
            for my $i ( $start_line .. $end_line ) {
                my $display_line = $i + 1;
                if ( $i == $line_num - 1 ) {

                    # Error line with >>> marker
                    $context .=
                      sprintf( ">>> %4d | %s\n", $display_line, $lines[$i] );
                }
                else {
                    # Normal context line with 4-space prefix
                    $context .=
                      sprintf( "    %4d | %s\n", $display_line, $lines[$i] );
                }
                if ( $i == $line_num - 1 ) {

# Add caret line pointing to failure position
# Account for: ">>> " (4) + "1234" (4) + " | " (3) = 11 chars before source text
                    my $spaces = " " x $col;
                    $context .= sprintf( "           %s^\n", $spaces );
                }
            }

            # Extract expected tokens from chart items at failure position
            my @items = $chart->items_ending_at($last_active_pos);
            my %expected_tokens;
            for my $item (@items) {
                my $rule    = $item->rule;
                my $dot_pos = $item->dot_pos;
                my @rhs     = $rule->rhs;

                # If dot is not at end, next symbol is expected
                if ( $dot_pos < scalar(@rhs) ) {
                    my $next_symbol = $rhs[$dot_pos];

                    # Convert array ref to string representation
                    if ( ref($next_symbol) eq 'ARRAY' ) {
                        $expected_tokens{ join( '|', @$next_symbol ) } = 1;
                    }
                    else {
                        $expected_tokens{$next_symbol} = 1;
                    }
                }
            }
            my @expected = sort keys %expected_tokens;

            warn(
"🔍 PARSING STOPPED: Reached position $last_active_pos of $input_length ("
                  . sprintf( "%.1f", 100 * $last_active_pos / $input_length )
                  . "%)\n"
                  . "📍 Source context:\n"
                  . $context
                  . "🔎 Expected tokens: "
                  . ( @expected ? join( ", ", @expected ) : "(none)" )
                  . "\n" );
        }

        # Check for semantic/type errors in the result
        if (!$result) {
            # Try to get errors from any failed parse elements
            $self->_display_semantic_errors($input);
        } elsif ($result && $result->can('has_errors') && $result->has_errors()) {
            # Parse succeeded but had warnings
            warn("⚠️  SEMANTIC WARNINGS:\n" . $result->format_errors($input) . "\n");
        } elsif ($result && $result->can('errors') && scalar($result->errors->@*) > 0) {
            # Result has errors array directly
            $self->_format_and_display_errors($result->errors, $input);
        }

        return $result;
    }

    method _display_semantic_errors($input) {
        # First priority: Display furthest-failure errors from diagnostic context
        # These are the most relevant since they represent where parsing actually got stuck
        if ($diagnostic_context && scalar($diagnostic_context->{furthest_errors}->@*) > 0) {
            my $pos = $diagnostic_context->{furthest_pos};
            warn("🔍 SEMANTIC ERRORS at furthest position $pos:\n");
            $self->_format_and_display_errors($diagnostic_context->{furthest_errors}, $input);
            return;  # Furthest errors are most relevant, skip others
        }

        # Display any errors collected during parsing
        if (@last_errors) {
            $self->_format_and_display_errors(\@last_errors, $input);
        }

        # Try to get errors from the semiring itself
        if ($semiring->can('collected_errors')) {
            my @errors = $semiring->collected_errors();
            if (@errors) {
                $self->_format_and_display_errors(\@errors, $input);
            }
        }

        # Also try to extract errors from composite semiring elements
        if ($semiring->can('semirings')) {
            for my $child_sr ($semiring->semirings->@*) {
                # Check for collected_errors method
                if ($child_sr->can('collected_errors')) {
                    my @errors = $child_sr->collected_errors();
                    if (@errors) {
                        $self->_format_and_display_errors(\@errors, $input);
                    }
                }
                # Also check add_id for errors
                if ($child_sr->can('add_id')) {
                    my $add_id = $child_sr->add_id;
                    if ($add_id->can('errors') && scalar($add_id->errors->@*) > 0) {
                        $self->_format_and_display_errors($add_id->errors, $input);
                    }
                }
            }
        }
    }

    # Get errors from last parse attempt
    method last_errors() {
        return @last_errors;
    }

    # Add an error to the error list
    method _add_error($error) {
        push @last_errors, $error;
    }

    # Collect errors from an element
    method _collect_errors_from_element($element) {
        return unless defined $element;
        if ($element->can('errors')) {
            my $errors = $element->errors;
            push @last_errors, $errors->@* if $errors && scalar($errors->@*) > 0;
        }
        # For composite elements, collect from children
        if ($element->can('elements')) {
            for my $child ($element->elements->@*) {
                $self->_collect_errors_from_element($child);
            }
        }
    }

    method _format_and_display_errors($errors, $input) {
        return unless $errors && scalar($errors->@*) > 0;

        my @lines;
        for my $err ($errors->@*) {
            my $msg = $err->{message} // 'Unknown semantic error';
            my $pos = $err->{start_pos} // 0;

            # Calculate line/column from position
            if (defined $input && $pos > 0) {
                my $line = 1;
                my $col = 1;
                for my $i (0 .. $pos - 1) {
                    if (substr($input, $i, 1) eq "\n") {
                        $line++;
                        $col = 1;
                    } else {
                        $col++;
                    }
                }
                push @lines, "  Line $line, Col $col: $msg";
            } else {
                push @lines, "  Position $pos: $msg";
            }
        }

        if (@lines) {
            warn("⚠️  SEMANTIC ERRORS:\n" . join("\n", @lines) . "\n");
        }
    }

    method process_position_string( $pos, $chart, $input_string ) {
        my @agenda = $chart->items_ending_at($pos);

        my $item;
        while ( $item = shift(@agenda) ) {
            my $element = $chart->get_element($item);
            next unless defined($element);

            if ( $item->complete ) {
                $self->complete( $item, $element, $chart, \@agenda );
            }
            else {
                my $next_sym = $item->next_symbol;
                if ( defined($next_sym) ) {
                    if ( $grammar->is_nonterminal($next_sym) ) {
                        $self->predict( $item, $next_sym, $chart, \@agenda );
                    }
                    else {
                        # Try to match terminal with lexeme support
                        # Pattern includes capture group from terminal_to_regex
                        my $pattern = $item->rule->terminal_to_regex($next_sym);
                        pos($input_string) = $pos;
                        if ( $input_string =~ qr/\G$pattern/ ) {
                            # Extract matched text and pattern name (if named capture)
                            # For named captures: %+ = (NAME => 'text'), for unnamed: $1 = 'text'
                            my ($pattern_name, $matched_text) = %+;
                            $matched_text //= $1;  # Fall back to $1 for unnamed captures

                            # Create appropriate Token subclass based on pattern_name
                            my $token_class = 'Chalk::Grammar::Token';
                            if ($pattern_name) {
                                if ($pattern_name =~ m/_OP$/) {
                                    # Operator patterns: ARITHMETIC_OP, NUM_COMPARE_OP, etc.
                                    $token_class = 'Chalk::Grammar::Token::Operator';
                                } elsif ($pattern_name eq 'INTEGER') {
                                    $token_class = 'Chalk::Grammar::Token::Int';
                                } elsif ($pattern_name eq 'FLOAT') {
                                    $token_class = 'Chalk::Grammar::Token::Float';
                                }
                            }
                            my $token = $token_class->new(
                                value => $matched_text,
                                pattern_name => $pattern_name
                            );

                            $self->scan( $item, $element, $chart, $pos, $token, $pattern_name );
                        }

                      # Aycock-Horspool optimization for nullable terminals:
                      # If the terminal can match empty string, also advance dot
                        if ( ref($next_sym) eq 'Regexp' && "" =~ $next_sym ) {
                            my $advanced_item = Chalk::EarleyItem->new(
                                start_pos => $item->start_pos,
                                rule      => $item->rule,
                                dot_pos   => $item->dot_pos + 1,
                                end_pos   => $item->end_pos
                            );

                            unless ( $chart->has_item($advanced_item) ) {
                                $chart->add_element( $advanced_item, $element );
                                push( @agenda, $advanced_item );
                            }
                        }
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

      # Get latest element from chart (handles updates from multiply operations)
        my $latest_element = $chart->get_element($completed_item);
        if ($latest_element) {
            $completed_element = $latest_element;
        }

        # Call semiring's on_complete() hook (polymorphic)
        # This allows semirings to perform actions when a rule completes
        # - Semantic: calls evaluate() on semantic actions and updates context
        # - Composite: delegates to all wrapped semirings
        # - Others: NOOP (returns element unchanged)
        $completed_element =
          $semiring->on_complete( $completed_item, $completed_element );

        # Update the chart with the (potentially modified) element
        $chart->add_element( $completed_item, $completed_element );

        # Use indexed lookups to get items waiting for this symbol
        # This avoids the expensive grep operations with isa checks
        my @waiting_for_lhs =
          $chart->items_waiting_for( $lhs, $completed_item->start_pos );
        my @leo_waiting =
          $chart->leo_items_waiting_for( $lhs, $completed_item->start_pos );

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
            push( $agenda->@*, $leo );
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

            # Always merge element (for disambiguation), only add to agenda if new
            my $has_existing = $chart->has_item($new_item);
            if ( $has_existing ) {
                my $old_element = $chart->get_element($new_item);

                # For complete items, call on_complete() on the new derivation BEFORE merging
                # This ensures add() can choose between fully-evaluated semantic elements,
                # not between an evaluated element and an unevaluated one.
                # Without SPPF, each derivation must get its own on_complete() call.
                if ( $new_item->complete ) {
                    $combined_element = $semiring->on_complete( $new_item, $combined_element );
                }

                my $merged = $chart->merge_element( $new_item, $combined_element );

                # If precedence filtering changed which derivation wins, we need to propagate
                # For complete items: propagate to parent items waiting for LHS
                # For incomplete items: re-add to agenda so it advances with valid element

                # Extract precedence elements from either Composite or direct Precedence
                my ($old_prec, $new_prec);
                if ($merged->can('elements') && $old_element->can('elements')) {
                    # Composite semiring case - precedence is first element
                    $old_prec = $old_element->elements->[0];
                    $new_prec = $combined_element->elements->[0];
                } elsif ($old_element->can('valid')) {
                    # Direct PrecedenceElement case
                    $old_prec = $old_element;
                    $new_prec = $combined_element;
                }

                # Check for invalid→valid transition
                my $validity_changed = $old_prec && $new_prec &&
                    $old_prec->can('valid') && $new_prec->can('valid') &&
                    !$old_prec->valid && $new_prec->valid;

                # For INCOMPLETE items with invalid→valid transition, re-add to agenda
                # This ensures they advance with the valid element, updating downstream items
                if ( !$new_item->complete && $validity_changed ) {
                    if ($ENV{DEBUG_PRECEDENCE}) {
                        warn "REQUEUE: " . $new_item->rule->lhs . "(" . $new_item->start_pos . "-" . $new_item->end_pos .
                             ") dot=" . $new_item->dot_pos . " for re-processing with valid element\n";
                    }
                    push( $agenda->@*, $new_item );
                }

                if ( $new_item->complete && $validity_changed ) {
                    # DEBUG
                    if ($ENV{DEBUG_PRECEDENCE}) {
                        warn "PROPAGATE: invalid→valid transition for " . $new_item->rule->lhs .
                             " at " . $new_item->start_pos . "-" . $new_item->end_pos . "\n";
                    }
                    # Propagate the valid parse up to parent items
                    my $lhs = $new_item->rule->lhs;
                    my @parent_waiting = $chart->items_waiting_for( $lhs, $new_item->start_pos );
                    if ($ENV{DEBUG_PRECEDENCE}) {
                        warn "  Looking for parents waiting for $lhs at pos " . $new_item->start_pos . ": found " . scalar(@parent_waiting) . "\n";
                    }
                    for my $parent_item (@parent_waiting) {
                        my $parent_element = $chart->get_element($parent_item);
                        next unless $parent_element;
                        my $parent_combined = $parent_element * $combined_element;
                        my $parent_new_item = Chalk::EarleyItem->new(
                            start_pos => $parent_item->start_pos,
                            rule      => $parent_item->rule,
                            dot_pos   => $parent_item->dot_pos + 1,
                            end_pos   => $new_item->end_pos
                        );
                        $chart->merge_element( $parent_new_item, $parent_combined );
                        # Add to agenda if not already there
                        unless ( $chart->has_completed($parent_new_item) ) {
                            push( $agenda->@*, $parent_new_item );
                        }
                    }
                }
            } else {
                $chart->add_element( $new_item, $combined_element );
                push( $agenda->@*, $new_item );
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
                push( $agenda->@*, $new_item );
            }
        }
    }

    method predict( $item, $nonterminal, $chart, $agenda ) {
        my $pos = $item->end_pos;

        # Check if we've already predicted this nonterminal from this rule at this position
        # Multiple rules can predict the same nonterminal, so we track by rule origin
        # NOTE: We only skip adding prediction items, NOT the nullable advancement below!
        unless ( $chart->has_predicted( $nonterminal, $pos, $item->rule->id ) ) {
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
                    my $rule_element =
                      $semiring->init_element_from_rule( $rule, $pos, $pos );
                    $chart->add_element( $predicted_item, $rule_element );
                    push( $agenda->@*, $predicted_item );
                }
            }
        }

        # Aycock-Horspool optimization: if the nonterminal is nullable,
        # we can also advance the dot past it immediately.
        # CRITICAL: This MUST happen unconditionally, even if we've already
        # predicted this nonterminal. The same nullable symbol (e.g., WS_OPT)
        # may appear multiple times in a rule (e.g., Block -> '{' WS_OPT StatementList WS_OPT '}')
        # and each occurrence must advance the dot past it.
        if ( $grammar->is_nullable($nonterminal) ) {
            my $advanced_item = Chalk::EarleyItem->new(
                start_pos => $item->start_pos,
                rule      => $item->rule,
                dot_pos   => $item->dot_pos + 1,
                end_pos   => $item->end_pos
            );

            # Get current element for this item (may have been updated by merge)
            my $current_element = $chart->get_element($item);
            if ($current_element) {
                if ( $chart->has_item($advanced_item) ) {
                    # Item exists - merge in case we have a better element
                    my $old_element = $chart->get_element($advanced_item);
                    my $merged = $chart->merge_element( $advanced_item, $current_element );

                    # Only re-add to agenda if merge changed validity (invalid→valid)
                    # This prevents infinite loops while still propagating valid elements
                    my ($old_prec, $new_prec);
                    if ($merged->can('elements') && $old_element->can('elements')) {
                        $old_prec = $old_element->elements->[0];
                        $new_prec = $current_element->elements->[0];
                    } elsif ($old_element->can('valid')) {
                        $old_prec = $old_element;
                        $new_prec = $current_element;
                    }
                    if ($old_prec && $new_prec &&
                        $old_prec->can('valid') && $new_prec->can('valid') &&
                        !$old_prec->valid && $new_prec->valid) {
                        push( $agenda->@*, $advanced_item );
                    }
                } else {
                    # New item
                    $chart->add_element( $advanced_item, $current_element );
                    push( $agenda->@*, $advanced_item );
                }
            }
        }
    }

    method scan( $item, $element, $chart, $pos, $matched_value, $pattern_name = undef ) {
        # $matched_value is a Chalk::Grammar::Token object (stringifies to its value)
        my $match_length = length($matched_value);
        my $scanned_item = Chalk::EarleyItem->new(
            start_pos => $item->start_pos,
            rule      => $item->rule,
            dot_pos   => $item->dot_pos + 1,
            end_pos   => $pos + $match_length
        );

        # Call semiring's on_scan() hook (polymorphic)
        # This allows semirings to handle scanned terminals appropriately:
        # - Semantic: multiplies with terminal element to accumulate in children
        # - Precedence: checks if token is_operator() to mark operators
        # - Others: creates new element with updated positions
        # $pattern_name is the name from named captures (e.g., 'IDENTIFIER')
        my $scanned_element = $semiring->on_scan( $item, $element, $pos, $matched_value, $pattern_name );

        $chart->add_element( $scanned_item, $scanned_element );
    }
}

1;
