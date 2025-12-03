# ABOUTME: Base class for IR-level types used by compute() for optimization
# ABOUTME: Part of type lattice: Top -> constants -> Bottom

use 5.42.0;
use experimental qw(class);

class Chalk::IR::Type {
    method is_constant() { return 0; }

    method value() {
        die "Cannot get value from non-constant type";
    }

    # meet() computes greatest lower bound (intersection) of two types
    # Default behavior: same type = self, different = Top
    method meet($other) {
        # Bottom absorbs everything
        return $other if $other isa Chalk::IR::Type::Bottom;
        # Top is identity for meet
        return $self if $other isa Chalk::IR::Type::Top;
        # Same exact type = self
        return $self if ref($self) eq ref($other);
        # Different types = Top (unknown)
        return Chalk::IR::Type::Top->top();
    }

    # join() computes least upper bound (union) of two types
    # This is the dual of meet() - while meet goes down the lattice, join goes up
    method join($other) {
        # Bottom is identity for join
        return $self if $other isa Chalk::IR::Type::Bottom;
        # Top absorbs everything in join
        return $other if $other isa Chalk::IR::Type::Top;
        # Same exact type = self
        return $self if ref($self) eq ref($other);
        # Different types = Top (unknown)
        return Chalk::IR::Type::Top->top();
    }
}

1;
