# ABOUTME: Bool represents a constant boolean value in IR
# ABOUTME: Uses builtin::true/builtin::false for native Perl booleans

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Bool :isa(Chalk::IR::Type) {
    field $value :param :reader;

    method is_constant() { return 1; }

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

        # Same boolean = that boolean
        if ($other isa blessed($self)) {
            return $self if $value == $other->value;
            # Different booleans = Top (unknown which)
            return Chalk::IR::Type::Top->top();
        }

        # Cross-type meet = Top
        return Chalk::IR::Type::Top->top();
    }
}

1;
