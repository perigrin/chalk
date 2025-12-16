# ABOUTME: Bool represents a constant boolean value in IR
# ABOUTME: Uses builtin::true/builtin::false for native Perl booleans

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Bool :isa(Chalk::IR::Type) {
    field $value :param :reader = undef;

    method is_constant() { defined($value) ? 1 : 0 }
    method is_top()      { !defined($value) ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub TRUE ($class) {
        state $singleton = $class->new(value => true);
        return $singleton;
    }

    sub FALSE ($class) {
        state $singleton = $class->new(value => false);
        return $singleton;
    }

    sub constant ($class, $val) {
        return $val ? $class->TRUE : $class->FALSE;
    }

    # meet() for TypeBool
    method meet($other) {
        # Handle global Bottom type - absorbs everything
        return $other if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - we're the result
        return $self if $other isa Chalk::IR::Type::Top;

        # BoolTop is identity for meet within bool domain
        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        # Two constants: same value = that constant, different = global Top
        if ($self->is_constant && $other isa blessed($self) && $other->is_constant) {
            return $self if $value == $other->value;
            # Different boolean values meet to global Top (preserves existing semantics)
            return Chalk::IR::Type::Top->top();
        }

        # Cross-type meet = global Top
        return Chalk::IR::Type::Top->top();
    }
}

1;
