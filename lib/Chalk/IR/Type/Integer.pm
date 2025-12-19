# ABOUTME: Integer represents integer values in IR type lattice
# ABOUTME: Supports IntTop (unknown), IntBot (error), and constants

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Integer :isa(Chalk::IR::Type) {
    field $value :param :reader = undef;
    field $is_bottom :param :reader = 0;
    field $bits   :param :reader = 64;
    field $signed :param :reader = 1;

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

    # meet() for TypeInteger with IntTop/IntBot lattice
    method meet($other) {
        # Handle global Bottom type
        return $other if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - we're the result
        return $self if $other isa Chalk::IR::Type::Top;

        # IntBot absorbs everything within integer domain
        return blessed($self)->BOTTOM() if $self->is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        # IntTop is identity for meet within integer domain
        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        # Two constants: same value = that constant, different = IntTop
        if ($self->is_constant && $other isa blessed($self) && $other->is_constant) {
            return $self if $value == $other->value;
            return blessed($self)->TOP();
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
        return $other if $self->is_bottom && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_bottom;

        # IntTop absorbs everything within integer domain
        return blessed($self)->TOP() if $self->is_top;
        return blessed($self)->TOP() if $other isa blessed($self) && $other->is_top;

        # Two constants: same value = that constant, different = IntTop
        if ($self->is_constant && $other isa blessed($self) && $other->is_constant) {
            return $self if $value == $other->value;
            return blessed($self)->TOP();
        }

        # Cross-type join = global Top
        return Chalk::IR::Type::Top->top();
    }

    # widen() for automatic Int->Float conversion
    method widen($other) {
        # If other is a Float type, widen this Integer to Float
        if ($other->isa('Chalk::IR::Type::Float')) {
            use Chalk::IR::Type::Float;
            # IntBot widens to FloatBot
            return Chalk::IR::Type::Float->BOTTOM() if $self->is_bottom;
            # IntTop widens to FloatTop
            return Chalk::IR::Type::Float->TOP() if $self->is_top;
            # Constant integer widens to constant float
            return Chalk::IR::Type::Float->constant($value + 0.0) if $self->is_constant;
        }

        # No widening needed for same type
        return $self;
    }

    # Narrow integer type support
    method min() {
        return 0 unless $signed;
        return -(1 << ($bits - 1));
    }

    method max() {
        return (1 << $bits) - 1 unless $signed;
        return (1 << ($bits - 1)) - 1;
    }

    method mask() {
        return (1 << $bits) - 1;
    }

    method sign_bit() {
        return 1 << ($bits - 1);
    }

    # Convenience constructors
    sub i8  ($class) { $class->new(bits => 8,  signed => 1) }
    sub i16 ($class) { $class->new(bits => 16, signed => 1) }
    sub i32 ($class) { $class->new(bits => 32, signed => 1) }
    sub i64 ($class) { $class->new(bits => 64, signed => 1) }
    sub u8  ($class) { $class->new(bits => 8,  signed => 0) }
    sub u16 ($class) { $class->new(bits => 16, signed => 0) }
    sub u32 ($class) { $class->new(bits => 32, signed => 0) }
    sub u64 ($class) { $class->new(bits => 64, signed => 0) }
    sub bool ($class) { $class->new(bits => 1, signed => 0) }
}

1;
