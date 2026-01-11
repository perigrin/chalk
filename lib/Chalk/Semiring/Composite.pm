# ABOUTME: Composite semiring pattern for combining multiple semirings
# ABOUTME: Provides delegation and composition of orthogonal semiring concerns
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Scalar::Util qw(refaddr);
use List::Util qw(all);
use Chalk::Base;

class Chalk::Semiring::CompositeElement :isa(Chalk::Element) {
    field $elements :param :reader;
    field $parent_semiring :param :reader = undef;  # Reference to parent Composite semiring

    method add( $other, $swap = undef ) {
        # SEQUENTIAL FILTERING: Each semiring filters independently
        # Call add() on each semiring in sequence, short-circuiting on first invalid result
        # This replaces the complex "leader pattern" with simple sequential iteration

        my @result_elements;
        my @self_elements = $elements->@*;
        my @other_elements = $other->elements->@*;

        for my $i (0..$#self_elements) {
            my $result = $self_elements[$i]->add($other_elements[$i]);
            push @result_elements, $result;

            # Short-circuit check: if result equals child's add_id, return composite's add_id
            # This happens when a filtering semiring (e.g., Precedence) rejects both options
            if ($parent_semiring && defined($parent_semiring->child_add_ids->[$i])) {
                if ($result->equals($parent_semiring->child_add_ids->[$i])) {
                    return $parent_semiring->add_id;
                }
            }
        }

        # All semirings processed successfully - determine consensus
        # Check if all semirings chose their self element
        my $all_chose_self = all {
            my $i = $_;
            refaddr($result_elements[$i]) == refaddr($self_elements[$i])
        } (0..$#result_elements);

        if ($all_chose_self) {
            return $self;  # All chose their self elements
        }

        # Check if all semirings chose their other element
        my $all_chose_other = all {
            my $i = $_;
            refaddr($result_elements[$i]) == refaddr($other_elements[$i])
        } (0..$#result_elements);

        if ($all_chose_other) {
            return $other;  # All chose their other elements
        }

        # No consensus - check if this is semantic disambiguation (allowed) or ambiguity (error)
        # SEMANTIC DISAMBIGUATION: When all validation layers mark both parses as valid,
        # Semantic is allowed to choose based on preferences (e.g., defined focus).
        # This is how the parser resolves highly ambiguous grammars.

        my $semirings = $parent_semiring ? $parent_semiring->semirings : undef;

        # Check if all elements that have 'valid' method say both are valid
        my $both_valid = 1;
        for my $i (0..$#result_elements) {
            if ($self_elements[$i]->can('valid') && $other_elements[$i]->can('valid')) {
                unless ($self_elements[$i]->valid && $other_elements[$i]->valid) {
                    $both_valid = 0;
                    last;
                }
            }
        }

        # If both are valid and we have a Semantic element that's choosing, allow it
        # This handles the ChalkIR case: [ChalkSyntax (validates both), Semantic (disambiguates)]
        if ($both_valid && $semirings) {
            for my $i (0..$#result_elements) {
                my $semiring = $semirings->[$i];
                # If this is a Semantic semiring and it made a choice, use it
                if (ref($semiring) eq 'Chalk::Semiring::Semantic') {
                    my $chose = refaddr($result_elements[$i]) == refaddr($self_elements[$i]) ? 'self' :
                               refaddr($result_elements[$i]) == refaddr($other_elements[$i]) ? 'other' : 'new';
                    if ($chose eq 'self') {
                        return $self;
                    } elsif ($chose eq 'other') {
                        return $other;
                    }
                }
            }
        }

        # True ambiguity - validation layers disagree or no Semantic to disambiguate
        my @diagnostics;
        for my $i (0..$#result_elements) {
            my $chose = refaddr($result_elements[$i]) == refaddr($self_elements[$i]) ? 'self' :
                       refaddr($result_elements[$i]) == refaddr($other_elements[$i]) ? 'other' : 'new';
            my $semiring_name = $semirings ? (ref($semirings->[$i]) =~ s/^Chalk::Semiring:://r) : "semiring[$i]";
            push @diagnostics, "$semiring_name chose $chose";
        }

        die "Ambiguous parse in Composite.add():\n  " . join("\n  ", @diagnostics) . "\n";
    }

    method multiply( $other, $swap = undef ) {
        # Delegate multiplication to each child element
        # Short-circuit if any child returns add_id
        my @results;
        for my $i (0..$#$elements) {
            my $result = $elements->[$i]->multiply($other->elements->[$i]);
            push @results, $result;

            # Short-circuit check: if result equals child's add_id, return composite's add_id
            if ($parent_semiring && defined($parent_semiring->child_add_ids->[$i])) {
                if ($result->equals($parent_semiring->child_add_ids->[$i])) {
                    return $parent_semiring->add_id;
                }
            }
        }

        return Chalk::Semiring::CompositeElement->new(
            elements => \@results,
            parent_semiring => $parent_semiring
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        return 0 unless scalar($elements->@*) == scalar($other->elements->@*);

        # All child elements must be equal
        for my $i (0..$#$elements) {
            return 0 unless $elements->[$i]->equals($other->elements->[$i]);
        }

        return 1;
    }

    method score() {
        # Sum scores from all elements that have them
        # In log-probability space, sum = product of probabilities
        my $total;  # Starts undef

        for my $elem ($elements->@*) {
            $total += $elem->score if $elem->can('score');
        }

        return $total;  # undef if no scores, number otherwise
    }

    method to_string(@args) {
        my @strs = map { "$_" } $elements->@*;
        return 'Composite[' . join(', ', @strs) . ']';
    }

    method element_at($index) {
        return $elements->[$index];
    }

    # Delegation methods: Forward context-related calls to semantic element
    # These methods are needed by semantic actions (e.g., ConditionalStatement.pm)
    # that expect to work with EvalContext objects
    # Note: Semantic element index depends on composite configuration

    method _semantic_element() {
        # Find the semantic element by looking for one with a 'context' method
        for my $elem ($elements->@*) {
            return $elem if $elem->can('context');
        }
        return undef;
    }

    method context() {
        # Delegate to semantic element
        my $sem = $self->_semantic_element();
        return $sem ? $sem->context : undef;
    }

    method child($index) {
        # Delegate to semantic element's context
        my $ctx = $self->context;
        return $ctx ? $ctx->child($index) : undef;
    }

    method children() {
        # Delegate to semantic element's context
        my $ctx = $self->context;
        return $ctx ? $ctx->children : [];
    }

    method env() {
        # Delegate to semantic element's context
        my $ctx = $self->context;
        return $ctx ? $ctx->env : {};
    }

    method extract() {
        # Delegate to semantic element
        my $sem = $self->_semantic_element();
        return $sem ? ($sem->can('extract') ? $sem->extract : undef) : undef;
    }
}

class Chalk::Semiring::Composite :isa(Chalk::Semiring) {
    field $semirings :param :reader;
    field $shared_context :param :reader = undef;
    field $mul_id :reader;
    field $add_id :reader;
    field $child_add_ids :reader;  # Store child add_ids for short-circuit checks

    ADJUST {
        # Create composite identity elements from child semirings
        my @mul_ids = map { $_->mul_id } $semirings->@*;
        $mul_id = Chalk::Semiring::CompositeElement->new(
            elements => \@mul_ids,
            parent_semiring => $self
        );

        my @add_ids = map { $_->add_id } $semirings->@*;
        $add_id = Chalk::Semiring::CompositeElement->new(
            elements => \@add_ids,
            parent_semiring => $self
        );

        # Store child add_ids for short-circuit comparison
        $child_add_ids = \@add_ids;
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # Initialize element from each child semiring
        my @elements;
        for my $semiring ($semirings->@*) {
            push @elements, $semiring->init_element_from_rule($rule, $start_pos, $end_pos, $matched_value);
        }

        return Chalk::Semiring::CompositeElement->new(
            elements => \@elements,
            parent_semiring => $self
        );
    }

    method multiply($x, $y) {
        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus($x, $y) {
        # For backward compatibility if called directly
        return $x->add($y);
    }

    # Delegate on_complete() to all wrapped semirings
    # This maintains polymorphism - each semiring can respond to rule completion
    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        # Extract elements from CompositeElement
        my @elements = $completed_element->elements->@*;

        # NOTE: We previously had short-circuit logic here, but it's been removed
        # because it interferes with the add() coordination. Invalid parses need
        # to complete (building placeholder IR) so that add() can later choose
        # the valid derivation. The Semantic evaluation is responsible for
        # handling invalid parses gracefully (not dying, just returning placeholder values).

        # Call on_complete() on each wrapped semiring with its corresponding element
        # Pass the full CompositeElement as 3rd parameter so semirings can access sibling data
        my @results;
        for my $i (0..$#$semirings) {
            my $semiring = $semirings->[$i];
            my $element = $elements[$i];

            # Delegate to child semiring, passing full CompositeElement for metadata access
            my $result = $semiring->on_complete($completed_item, $element, $completed_element);
            push @results, $result;
        }

        # Return new CompositeElement with updated elements
        return Chalk::Semiring::CompositeElement->new(
            elements => \@results,
            parent_semiring => $self
        );
    }

    # Delegate on_scan() to all wrapped semirings
    # This maintains polymorphism - each semiring can respond to terminal scanning
    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # Extract elements from CompositeElement
        my @elements = $element->elements->@*;

        # Call on_scan() on each wrapped semiring with its corresponding element
        my @results;
        for my $i (0..$#$semirings) {
            my $semiring = $semirings->[$i];
            my $child_element = $elements[$i];

            # Delegate to child semiring (which may handle terminals differently)
            my $result = $semiring->on_scan($item, $child_element, $pos, $matched_value, $pattern_name);
            push @results, $result;
        }

        # Return new CompositeElement with updated elements
        return Chalk::Semiring::CompositeElement->new(
            elements => \@results,
            parent_semiring => $self
        );
    }

    # Override to propagate diagnostic context to all child semirings
    method set_diagnostic_context($ctx) {
        # Call parent implementation
        $self->SUPER::set_diagnostic_context($ctx);

        # Propagate to all child semirings
        for my $child_sr ($semirings->@*) {
            if ($child_sr->can('set_diagnostic_context')) {
                $child_sr->set_diagnostic_context($ctx);
            }
        }
    }
}

1;
