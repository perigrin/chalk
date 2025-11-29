# ABOUTME: TypeInteger represents a constant integer value in IR
# ABOUTME: Used by compute() to enable constant folding in peephole()

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeInteger :isa(Chalk::IR::Type) {
    field $value :param :reader;

    method is_constant() { return 1; }

    sub constant {
        my $class = shift // __PACKAGE__;
        my $val = shift;
        return $class->new(value => $val);
    }
}

1;
