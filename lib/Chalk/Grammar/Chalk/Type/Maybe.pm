# ABOUTME: Maybe type for nullable references (T or undef) in Chalk type system
# ABOUTME: Wrapper type supporting covariant subtyping: Maybe[T] <: Maybe[U] if T <: U

use 5.42.0;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::Maybe :isa(Chalk::Grammar::Chalk::Type) {
    # The wrapped type
    field $inner_type :param :reader;

    method unwrap() {
        return $inner_type;
    }

    method name() {
        return 'Maybe[' . $inner_type->name() . ']';
    }

    method is_subtype_of($other) {
        # Maybe[T] <: Maybe[U] if T <: U (covariant)
        if ($other isa Chalk::Grammar::Chalk::Type::Maybe) {
            return $inner_type->is_subtype_of($other->inner_type());
        }

        # Maybe[T] <: Undef (can be undef)
        return $other isa Chalk::Grammar::Chalk::Type::Undef;
    }
}

1;
