# ABOUTME: Code represents subroutine/code reference values in IR type lattice
# ABOUTME: Maps to CV* in XS code generation

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Code :isa(Chalk::IR::Type) {
    field $param_types :param :reader = undef;
    field $return_type :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { 0 }  # Code refs are not constants
    method is_top()      { (!defined($param_types) && !defined($return_type) && !$is_bottom) ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }

    sub of ($class, $params, $ret) {
        return $class->new(param_types => $params, return_type => $ret);
    }

    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $self if $other isa Chalk::IR::Type::Top;

        return blessed($self)->BOTTOM() if $is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        return Chalk::IR::Type::Top->top();
    }
}

1;
