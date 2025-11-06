# ABOUTME: Base class for the Chalk grammar type system implementing the latent type lattice
# ABOUTME: Provides common type operations like subtyping, compatibility, and type names

use 5.042;
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
}

1;
