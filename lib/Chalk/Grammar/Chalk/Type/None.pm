# ABOUTME: Bottom type in the Chalk type lattice - None is a subtype of all types
# ABOUTME: Implements is_bottom() and is subtype of everything

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::None :isa(Chalk::Grammar::Chalk::Type) {
    # None is the bottom type in the type lattice
    # None is a subtype of all types

    method is_bottom() {
        return 1;
    }

    method is_subtype_of($other) {
        # None is a subtype of everything
        return 1;
    }
}

1;
