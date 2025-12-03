# ABOUTME: TypeInteger represents integer values in IR type lattice
# ABOUTME: Supports IntTop (unknown), IntBot (error), and constants

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::TypeInteger :isa(Chalk::IR::Type) {
    field $value :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { (defined($value) && !$is_bottom) ? 1 : 0 }
    method is_top()      { (!defined($value) && !$is_bottom) ? 1 : 0 }

    sub TOP {
        state $singleton = __PACKAGE__->new();
        return $singleton;
    }

    sub BOTTOM {
        state $singleton = __PACKAGE__->new(is_bottom => 1);
        return $singleton;
    }

    sub constant {
        my $class = shift // __PACKAGE__;
        my $val = shift;
        return $class->new(value => $val);
    }

    # meet() for TypeInteger with IntTop/IntBot lattice
    method meet($other) {
        # Handle global Bottom type
        return $other if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - we're the result
        return $self if $other isa Chalk::IR::Type::Top;

        # IntBot absorbs everything within integer domain
        return __PACKAGE__->BOTTOM() if $self->is_bottom;
        return __PACKAGE__->BOTTOM() if $other isa __PACKAGE__ && $other->is_bottom;

        # IntTop is identity for meet within integer domain
        return $other if $self->is_top && $other isa __PACKAGE__;
        return $self if $other isa __PACKAGE__ && $other->is_top;

        # Two constants: same value = that constant, different = IntTop
        if ($self->is_constant && $other isa __PACKAGE__ && $other->is_constant) {
            return $self if $value == $other->value;
            return __PACKAGE__->TOP();
        }

        # Cross-type meet = global Top
        return Chalk::IR::Type::Top->top();
    }

    # join() for TypeInteger with IntTop/IntBot lattice
    method join($other) {
        # Handle global Bottom type - identity for join
        return $self if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - absorbs in join
        return $other if $other isa Chalk::IR::Type::Top;

        # IntBot is identity for join within integer domain
        return $other if $self->is_bottom && $other isa __PACKAGE__;
        return $self if $other isa __PACKAGE__ && $other->is_bottom;

        # IntTop absorbs everything within integer domain
        return __PACKAGE__->TOP() if $self->is_top;
        return __PACKAGE__->TOP() if $other isa __PACKAGE__ && $other->is_top;

        # Two constants: same value = that constant, different = IntTop
        if ($self->is_constant && $other isa __PACKAGE__ && $other->is_constant) {
            return $self if $value == $other->value;
            return __PACKAGE__->TOP();
        }

        # Cross-type join = global Top
        return Chalk::IR::Type::Top->top();
    }
}

1;
