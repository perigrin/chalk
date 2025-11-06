# ABOUTME: Top type in the Chalk type lattice - all types are subtypes of Any
# ABOUTME: Implements is_top() and accepts all types as subtypes

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::Any :isa(Chalk::Grammar::Chalk::Type) {
    # Any is the top type in the type lattice
    # All types are subtypes of Any

    method is_top() {
        return 1;
    }

    method is_subtype_of($other) {
        # Any is only a subtype of itself
        return ref($other) eq 'Chalk::Grammar::Chalk::Type::Any';
    }
}

1;
