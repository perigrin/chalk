# ABOUTME: Array represents array values in IR type lattice
# ABOUTME: Maps to AV* in XS code generation

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Array :isa(Chalk::IR::Type) {
    field $element_type :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { 0 }  # Arrays are not constants
    method is_top()      { (!defined($element_type) && !$is_bottom) ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }

    sub of ($class, $elem_type) {
        return $class->new(element_type => $elem_type);
    }

    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $self if $other isa Chalk::IR::Type::Top;

        return blessed($self)->BOTTOM() if $is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        # Same array type with element types - meet element types
        if ($other isa blessed($self) && defined($element_type) && defined($other->element_type)) {
            my $meet_elem = $element_type->meet($other->element_type);
            return blessed($self)->of($meet_elem);
        }

        return Chalk::IR::Type::Top->top();
    }
}

1;
