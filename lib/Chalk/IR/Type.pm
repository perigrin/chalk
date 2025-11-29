# ABOUTME: Base class for IR-level types used by compute() for optimization
# ABOUTME: Part of type lattice: Top -> constants -> Bottom

use 5.42.0;
use experimental qw(class);

class Chalk::IR::Type {
    method is_constant() { return 0; }

    method value() {
        die "Cannot get value from non-constant type";
    }
}

1;
