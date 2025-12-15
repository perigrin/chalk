# ABOUTME: Ctrl represents a control token in IR
# ABOUTME: Singleton type for control flow (has no data value)

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Ctrl :isa(Chalk::IR::Type) {
    method is_constant() { return 1; }
    method value() { return undef; }

    sub CTRL ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    # meet() for TypeCtrl - control tokens
    method meet($other) {
        # Handle global Bottom type - absorbs everything
        return $other if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - we're the result
        return $self if $other isa Chalk::IR::Type::Top;
        # Ctrl meet Ctrl = Ctrl (singleton)
        return $self if $other isa blessed($self);
        # Cross-type meet = Top
        return Chalk::IR::Type::Top->top();
    }
}

1;
