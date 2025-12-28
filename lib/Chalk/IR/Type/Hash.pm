# ABOUTME: Hash represents hash values in IR type lattice
# ABOUTME: Maps to HV* in XS code generation

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Hash :isa(Chalk::IR::Type) {
    field $value_type :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { 0 }  # Hashes are not constants
    method is_top()      { (!defined($value_type) && !$is_bottom) ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }

    sub of ($class, $val_type) {
        return $class->new(value_type => $val_type);
    }

    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $self if $other isa Chalk::IR::Type::Top;

        return blessed($self)->BOTTOM() if $self->is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        # Same hash type with value types - meet value types
        if ($other isa blessed($self) && defined($value_type) && defined($other->value_type)) {
            my $meet_val = $value_type->meet($other->value_type);
            return blessed($self)->of($meet_val);
        }

        return Chalk::IR::Type::Top->top();
    }
}

1;
