# ABOUTME: Hash type representing hash values with parameterized value type
# ABOUTME: Implements Hash <: List <: Any subtyping chain with value_type parameter

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::Hash :isa(Chalk::Grammar::Chalk::Type) {
    # Hash represents hash values
    # Hash <: List <: Any
    # Parameterized by value_type

    field $value_type :param :reader;

    method is_subtype_of($other) {
        # Hash <: Hash (reflexive)
        # Hash <: List
        # Hash <: Any (transitive)
        return ref($other) eq 'Chalk::Grammar::Chalk::Type::Hash' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::List' ||
               ref($other) eq 'Chalk::Grammar::Chalk::Type::Any';
    }

    method meet($other) {
        # Handle boundary cases
        return $other if $other->is_bottom();
        return $self if $other->is_top();

        # Hash meet Hash: covariant value types
        if (ref($other) eq 'Chalk::Grammar::Chalk::Type::Hash') {
            my $val_meet = $value_type->meet($other->value_type);
            return Chalk::Grammar::Chalk::Type::Hash->new(value_type => $val_meet);
        }

        # Hash meet non-Hash: incompatible types return None
        return Chalk::Grammar::Chalk::Type::None->new();
    }

    method join($other) {
        # Handle boundary cases
        return $self if $other->is_bottom();
        return $other if $other->is_top();

        # Hash join Hash: covariant value types
        if (ref($other) eq 'Chalk::Grammar::Chalk::Type::Hash') {
            my $val_join = $value_type->join($other->value_type);
            return Chalk::Grammar::Chalk::Type::Hash->new(value_type => $val_join);
        }

        # Hash join non-Hash: find common supertype
        # Both Array and Hash are under List
        my $list = Chalk::Grammar::Chalk::Type::List->new();
        if ($other->is_subtype_of($list)) {
            return $list;
        }

        # Otherwise return Any
        return Chalk::Grammar::Chalk::Type::Any->new();
    }
}

1;
