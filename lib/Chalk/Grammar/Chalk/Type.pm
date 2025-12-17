# ABOUTME: Base class for the Chalk grammar type system implementing the latent type lattice
# ABOUTME: Provides common type operations like subtyping, compatibility, and type names

use 5.42.0;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type {
    # Base class for all types in the Chalk grammar type system
    # Based on: https://gist.github.com/perigrin/c4780a7511ba1421e49a4a8b385aaa3d

    method name() {
        # Return the canonical name of this type
        # Subclasses override this
        my $class = ref($self) || $self;
        # Extract class name after Chalk::Grammar::Chalk::Type:: prefix
        if ($class =~ qr/^Chalk::Grammar::Chalk::Type::(.+)$/) {
            return $1;
        }
        return $class;
    }

    method is_subtype_of($other) {
        # Check if this type is a subtype of another type
        # Default: only if same type
        return ref($self) eq ref($other);
    }

    method is_top() {
        # Is this the top type (Any)?
        return 0;
    }

    method is_bottom() {
        # Is this the bottom type (None)?
        return 0;
    }

    method is_compatible_with($other) {
        # Two types are compatible if one is a subtype of the other
        return $self->is_subtype_of($other) || $other->is_subtype_of($self);
    }

    method round_trip_preserves($value) {
        # Check if value round-trips through type coercion without loss
        # Default: always true (permissive)
        # Subclasses override for stricter checks
        return 1;
    }

    method satisfies_contract($value) {
        # Check if value satisfies operational contracts for this type
        # Default: always true (permissive)
        # Subclasses override for specific contracts
        return 1;
    }

    method check_membership($value) {
        # Type membership requires BOTH:
        # 1. Syntactic preservation (round-trip)
        # 2. Semantic fulfillment (contracts)
        return $self->round_trip_preserves($value) &&
               $self->satisfies_contract($value);
    }

    method meet($other) {
        # Greatest lower bound (infimum/intersection)
        # Default implementation uses subtype relationships
        # Subclasses override for type-specific behavior

        # Handle None (bottom) - absorbs everything
        return $other if $other->is_bottom();
        return $self if $self->is_bottom();

        # Handle Any (top) - identity for meet
        return $self if $other->is_top();
        return $other if $self->is_top();

        # Same type - return self (idempotence)
        return $self if ref($self) eq ref($other);

        # Check subtype relationships
        return $self if $self->is_subtype_of($other);
        return $other if $other->is_subtype_of($self);

        # Incompatible types - return None (bottom)
        return Chalk::Grammar::Chalk::Type::None->new();
    }

    method join($other) {
        # Least upper bound (supremum/union)
        # Default implementation uses subtype relationships
        # Subclasses override for type-specific behavior

        # Handle None (bottom) - identity for join
        return $self if $other->is_bottom();
        return $other if $self->is_bottom();

        # Handle Any (top) - absorbs everything
        return $other if $other->is_top();
        return $self if $self->is_top();

        # Same type - return self (idempotence)
        return $self if ref($self) eq ref($other);

        # Check subtype relationships
        return $other if $self->is_subtype_of($other);
        return $self if $other->is_subtype_of($self);

        # Incompatible types - need to find common supertype
        # For types in different branches, this requires walking up the hierarchy
        # Default to Any if we can't find a better common supertype
        return $self->_find_common_supertype($other);
    }

    method _find_common_supertype($other) {
        # Walk up the type hierarchy to find the least common supertype
        # This is a simple implementation that checks known ancestors

        # Both under Scalar?
        my $scalar = Chalk::Grammar::Chalk::Type::Scalar->new();
        if ($self->is_subtype_of($scalar) && $other->is_subtype_of($scalar)) {
            return $scalar;
        }

        # Both under List?
        my $list = Chalk::Grammar::Chalk::Type::List->new();
        if ($self->is_subtype_of($list) && $other->is_subtype_of($list)) {
            return $list;
        }

        # Default to Any
        return Chalk::Grammar::Chalk::Type::Any->new();
    }
}

1;
