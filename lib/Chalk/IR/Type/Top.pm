# ABOUTME: Top type representing unknown/unanalyzed values in IR
# ABOUTME: Singleton - call Chalk::IR::Type::Top->top() to access

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::Top :isa(Chalk::IR::Type) {
    # Class method to get the singleton TOP instance
    # Uses state variable to ensure only one instance is created
    sub top {
        my $class = shift // __PACKAGE__;
        state $singleton = Chalk::IR::Type::Top->new();
        return $singleton;
    }

    # Top is identity for meet - return the other type
    # Exception: Bottom absorbs everything
    method meet($other) {
        return $other if $other isa Chalk::IR::Type::Bottom;
        return $other;
    }

    # Top absorbs everything in join - always returns Top
    method join($other) {
        return $self;
    }
}

1;
