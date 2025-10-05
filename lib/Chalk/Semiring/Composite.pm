# ABOUTME: Composite semiring pattern for combining multiple semirings
# ABOUTME: Provides delegation and composition of orthogonal semiring concerns
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::CompositeElement :isa(Chalk::Element) {
    field $elements :param :reader;

    method add( $other, $swap = undef ) {
        # Delegate addition to each child element
        my @results;
        for my $i (0..$#$elements) {
            push @results, $elements->[$i]->add($other->elements->[$i]);
        }

        return Chalk::Semiring::CompositeElement->new(
            elements => \@results
        );
    }

    method multiply( $other, $swap = undef ) {
        # Delegate multiplication to each child element
        my @results;
        for my $i (0..$#$elements) {
            push @results, $elements->[$i]->multiply($other->elements->[$i]);
        }

        return Chalk::Semiring::CompositeElement->new(
            elements => \@results
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
        # Return first element's score that has one
        # If no element has a score() method, return nothing
        for my $elem ($elements->@*) {
            return $elem->score if $elem->can('score');
        }
        return;
    }

    method to_string(@) {
        my @strs = map { "$_" } $elements->@*;
        return 'Composite[' . join(', ', @strs) . ']';
    }

    method element_at($index) {
        return $elements->[$index];
    }
}

class Chalk::Semiring::Composite :isa(Chalk::Semiring) {
    field $semirings :param :reader;
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        # Create composite identity elements from child semirings
        my @mul_ids = map { $_->mul_id } $semirings->@*;
        $mul_id = Chalk::Semiring::CompositeElement->new(
            elements => \@mul_ids
        );

        my @add_ids = map { $_->add_id } $semirings->@*;
        $add_id = Chalk::Semiring::CompositeElement->new(
            elements => \@add_ids
        );
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        # Initialize element from each child semiring
        my @elements;
        for my $semiring ($semirings->@*) {
            push @elements, $semiring->init_element_from_rule($rule, $start_pos, $end_pos);
        }

        return Chalk::Semiring::CompositeElement->new(
            elements => \@elements
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
}

1;
