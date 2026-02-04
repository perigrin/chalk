# ABOUTME: Memory represents memory state in IR type lattice
# ABOUTME: Tracks memory slices by alias class for aliasing analysis

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Memory :isa(Chalk::IR::Type) {
    field $alias_class :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { 0 }  # Memory states are not constant values
    method is_top() { (!defined($alias_class) && !$is_bottom) ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }

    # meet() for TypeMemory
    # Meet finds the most specific memory state
    method meet($other) {
        # Handle global Bottom type - absorbs everything
        return $other if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - we're the result
        return $self if $other isa Chalk::IR::Type::Top;

        # MemBot absorbs everything within memory domain
        return blessed($self)->BOTTOM() if $is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        # MemTop is identity for meet within memory domain
        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        # Both are memory slices
        if ($other isa blessed($self)) {
            # Different alias classes -> incompatible -> MemTop
            if (defined($alias_class) && defined($other->alias_class)
                && $alias_class != $other->alias_class) {
                return blessed($self)->TOP();
            }

            # Same alias class
            my $result_class = $alias_class // $other->alias_class;
            return blessed($self)->new(alias_class => $result_class);
        }

        # Cross-type meet = global Top
        return Chalk::IR::Type::Top->top();
    }

    # join() for TypeMemory
    # Join finds the least specific memory state
    method join($other) {
        # Handle global Bottom type - identity for join
        return $self if $other isa Chalk::IR::Type::Bottom;
        # Handle global Top type - absorbs in join
        return $other if $other isa Chalk::IR::Type::Top;

        # MemBot is identity for join within memory domain
        return $other if $is_bottom && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_bottom;

        # MemTop absorbs everything within memory domain
        return blessed($self)->TOP() if $self->is_top;
        return blessed($self)->TOP() if $other isa blessed($self) && $other->is_top;

        # Both are memory slices
        if ($other isa blessed($self)) {
            # Different alias classes -> unknown which -> MemTop
            if (defined($alias_class) && defined($other->alias_class)
                && $alias_class != $other->alias_class) {
                return blessed($self)->TOP();
            }

            # Same alias class
            my $result_class = $alias_class // $other->alias_class;
            return blessed($self)->new(alias_class => $result_class);
        }

        # Cross-type join = global Top
        return Chalk::IR::Type::Top->top();
    }
}

1;
