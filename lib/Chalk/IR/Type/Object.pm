# ABOUTME: Object represents blessed reference values in IR type lattice
# ABOUTME: Parameterized by class name - maps to SV* in XS code generation

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

class Chalk::IR::Type::Object :isa(Chalk::IR::Type) {
    field $class_name :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { 0 }  # Objects are not constants
    method is_top()      { (!defined($class_name) && !$is_bottom) ? 1 : 0 }

    sub TOP ($class) {
        state $singleton = $class->new();
        return $singleton;
    }

    sub BOTTOM ($class) {
        state $singleton = $class->new(is_bottom => 1);
        return $singleton;
    }

    sub of ($class, $cls_name) {
        return $class->new(class_name => $cls_name);
    }

    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $self if $other isa Chalk::IR::Type::Top;

        return blessed($self)->BOTTOM() if $is_bottom;
        return blessed($self)->BOTTOM() if $other isa blessed($self) && $other->is_bottom;

        return $other if $self->is_top && $other isa blessed($self);
        return $self if $other isa blessed($self) && $other->is_top;

        # Same class name = same type, different = Object TOP
        if ($other isa blessed($self) && defined($class_name) && defined($other->class_name)) {
            return $self if $class_name eq $other->class_name;
            return blessed($self)->TOP();
        }

        return Chalk::IR::Type::Top->top();
    }
}

1;
