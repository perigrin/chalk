# ABOUTME: Undef represents the undefined value in IR type lattice
# ABOUTME: Maps to SV* (&PL_sv_undef) in XS code generation

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Undef :isa(Chalk::IR::Type) {
    method is_constant() { 1 }  # Undef is a constant (the undefined value)
    method is_top()      { 0 }

    method value() { return undef; }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $self if $other isa Chalk::IR::Type::Top;

        # Undef meets Undef = Undef
        return $self if $other isa blessed($self);

        # Undef meets other type = global Top (different types)
        return Chalk::IR::Type::Top->top();
    }
}

1;
