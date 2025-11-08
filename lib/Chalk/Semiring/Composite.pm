# ABOUTME: Composite semiring pattern for combining multiple semirings
# ABOUTME: Provides delegation and composition of orthogonal semiring concerns
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::CompositeElement :isa(Chalk::Element) {
    field $elements :param :reader;
    field $parent_semiring :param :reader = undef;  # Reference to parent Composite semiring

    method add( $other, $swap = undef ) {
        # Delegate addition to each child element
        # Short-circuit if any child returns add_id
        my @results;
        for my $i (0..$#$elements) {
            my $result = $elements->[$i]->add($other->elements->[$i]);
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

    # Delegation methods: Forward context-related calls to semantic element (index 2)
    # These methods are needed by semantic actions (e.g., ConditionalStatement.pm)
    # that expect to work with EvalContext objects

    method context() {
        # Delegate to semantic element (elements[2] in ChalkIR architecture)
        return $elements->[2]->can('context') ? $elements->[2]->context : undef;
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
        return $elements->[2]->can('extract') ? $elements->[2]->extract : undef;
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

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        # Initialize element from each child semiring
        my @elements;
        for my $semiring ($semirings->@*) {
            push @elements, $semiring->init_element_from_rule($rule, $start_pos, $end_pos);
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
    method on_complete($completed_item, $completed_element) {
        # Extract elements from CompositeElement
        my @elements = $completed_element->elements->@*;

        # Call on_complete() on each wrapped semiring with its corresponding element
        my @results;
        for my $i (0..$#$semirings) {
            my $semiring = $semirings->[$i];
            my $element = $elements[$i];

            # Delegate to child semiring (which may be NOOP or may do work)
            my $result = $semiring->on_complete($completed_item, $element);
            push @results, $result;
        }

        # Return new CompositeElement with updated elements
        return Chalk::Semiring::CompositeElement->new(
            elements => \@results,
            parent_semiring => $self
        );
    }
}

1;
