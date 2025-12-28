# ABOUTME: Scalar represents any scalar value in IR type lattice
# ABOUTME: Union of String|Integer|Float|Bool|Undef|Ref - maps to SV* in XS

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Scalar :isa(Chalk::IR::Type) {
    field $is_bottom :param :reader = 0;

    method is_constant() { 0 }  # Scalar is a type category, not a constant
    method is_top()      { !$is_bottom ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }

    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $self if $other isa Chalk::IR::Type::Top;

        return blessed($self)->BOTTOM() if $self->is_bottom;

        # Scalar meets Scalar = Scalar
        return $self if $other isa blessed($self);

        # Scalar meets specific scalar type = that type (narrowing)
        # Integer, Float, String, Bool, Undef, Ref are all scalars
        for my $scalar_type (qw(Integer Float String Bool Undef Ref)) {
            my $type_class = "Chalk::IR::Type::$scalar_type";
            return $other if $other isa $type_class;
        }

        return Chalk::IR::Type::Top->top();
    }
}

1;
