# ABOUTME: List node for holding multiple expression values
# ABOUTME: Used for expression lists, function arguments, and list assignment
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::List :isa(Chalk::IR::Node::Base) {
    field $elements :param :reader = [];  # Array of IR nodes

    method op() { 'List' }

    method to_hash() {
        my @element_ids = map { $_->id } $elements->@*;
        return {
            id     => $self->id,
            op     => 'List',
            inputs => $self->inputs,
            attributes => {
                element_count => scalar($elements->@*),
                element_ids   => \@element_ids,
            },
        };
    }

    method execute($context) {
        # Evaluate all elements and return as array ref
        my @values;
        for my $elem ($elements->@*) {
            my $value = $context->("node:" . $elem->id);
            push @values, $value;
        }
        return \@values;
    }

    # Return the number of elements
    method length() {
        return scalar($elements->@*);
    }

    # Get element at index
    method element_at($index) {
        return $elements->[$index];
    }

    method peephole($graph = undef) {
        return $self;
    }
}

1;
