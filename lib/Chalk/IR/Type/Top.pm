# ABOUTME: Top type representing unknown/unanalyzed values in IR
# ABOUTME: Singleton - use Chalk::IR::Type::Top->TOP to access

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::Top :isa(Chalk::IR::Type) {
    my $TOP;

    sub TOP {
        my $class = shift // __PACKAGE__;
        $TOP //= $class->new();
    }
}

1;
