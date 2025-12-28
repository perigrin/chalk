# ABOUTME: String represents string values in IR type lattice
# ABOUTME: Maps to SV* in XS code generation

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::String :isa(Chalk::IR::Type) {
    field $value :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { (defined($value) && !$is_bottom) ? 1 : 0 }
    method is_top()      { (!defined($value) && !$is_bottom) ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }

    sub constant ($class, $val) {
        return $class->new(value => $val);
    }

    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $self if $other isa Chalk::IR::Type::Top;

        return blessed($self)->BOTTOM() if $self->is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        if ($self->is_constant && $other isa blessed($self) && $other->is_constant) {
            return $self if $value eq $other->value;
            return blessed($self)->TOP();
        }

        return Chalk::IR::Type::Top->top();
    }
}

1;
