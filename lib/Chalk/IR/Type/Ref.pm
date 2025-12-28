# ABOUTME: Ref represents reference values in IR type lattice
# ABOUTME: Parameterized by referent type - maps to SV* in XS code generation

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Ref :isa(Chalk::IR::Type) {
    field $referent_type :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { 0 }  # Refs are not constants
    method is_top()      { (!defined($referent_type) && !$is_bottom) ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }

    sub of ($class, $ref_type) {
        return $class->new(referent_type => $ref_type);
    }

    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $self if $other isa Chalk::IR::Type::Top;

        return blessed($self)->BOTTOM() if $self->is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        # Same ref type with referent types - meet referent types
        if ($other isa blessed($self) && defined($referent_type) && defined($other->referent_type)) {
            my $meet_ref = $referent_type->meet($other->referent_type);
            return blessed($self)->of($meet_ref);
        }

        return Chalk::IR::Type::Top->top();
    }
}

1;
