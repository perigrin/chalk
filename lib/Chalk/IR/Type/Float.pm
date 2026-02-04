# ABOUTME: Float represents floating-point values in IR type lattice
# ABOUTME: Supports FloatTop (unknown), FloatBot (error), and constants

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Float :isa(Chalk::IR::Type) {
    field $value :param :reader = undef;
    field $is_bottom :param :reader = 0;
    field $bits :param :reader = 64;

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

    # meet() for TypeFloat with FloatTop/FloatBot lattice
    method meet($other) {
        # Handle global Bottom type
        return $other if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - we're the result
        return $self if $other isa Chalk::IR::Type::Top;

        # FloatBot absorbs everything within float domain
        return blessed($self)->BOTTOM() if $is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        # FloatTop is identity for meet within float domain
        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        # Two constants: same value = that constant, different = FloatTop
        if ($self->is_constant && $other isa blessed($self) && $other->is_constant) {
            return $self if $value == $other->value;
            return blessed($self)->TOP();
        }

        # Cross-type meet = global Top
        return Chalk::IR::Type::Top->top();
    }

    # join() for TypeFloat with FloatTop/FloatBot lattice
    method join($other) {
        # Handle global Bottom type - identity for join
        return $self if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - absorbs in join
        return $other if $other isa Chalk::IR::Type::Top;

        # FloatBot is identity for join within float domain
        return $other if $is_bottom && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_bottom;

        # FloatTop absorbs everything within float domain
        return blessed($self)->TOP() if $self->is_top;
        return blessed($self)->TOP() if $other isa blessed($self) && $other->is_top;

        # Two constants: same value = that constant, different = FloatTop
        if ($self->is_constant && $other isa blessed($self) && $other->is_constant) {
            return $self if $value == $other->value;
            return blessed($self)->TOP();
        }

        # Cross-type join = global Top
        return Chalk::IR::Type::Top->top();
    }

    # widen() for Float - Float is already widest numeric type, so returns self
    method widen($other) {
        # Float doesn't widen further - it's the widest numeric type
        return $self;
    }

    # Convenience constructors
    sub f32 ($class) { $class->new(bits => 32) }
    sub f64 ($class) { $class->new(bits => 64) }
}

1;
