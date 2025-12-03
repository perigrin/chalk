# ABOUTME: Bottom type representing error states in IR (e.g., division by zero)
# ABOUTME: Singleton - use Chalk::IR::Type::Bottom->BOTTOM to access

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::Bottom :isa(Chalk::IR::Type) {
    my $BOTTOM;

    sub BOTTOM {
        my $class = shift // __PACKAGE__;
        $BOTTOM //= $class->new();
    }

    # Bottom absorbs everything in meet
    method meet($other) {
        return $self;
    }

    # Bottom is identity for join - return the other type
    method join($other) {
        return $other;
    }
}

1;
