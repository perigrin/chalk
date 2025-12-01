# ABOUTME: TypeInteger represents integer values in IR type lattice
# ABOUTME: Supports IntTop (unknown), IntBot (error), and constants

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeInteger :isa(Chalk::IR::Type) {
    field $value :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { (defined($value) && !$is_bottom) ? 1 : 0 }
    method is_top()      { (!defined($value) && !$is_bottom) ? 1 : 0 }

    sub TOP {
        state $singleton = __PACKAGE__->new();
        return $singleton;
    }

    sub BOTTOM {
        state $singleton = __PACKAGE__->new(is_bottom => 1);
        return $singleton;
    }

    sub constant {
        my $class = shift // __PACKAGE__;
        my $val = shift;
        return $class->new(value => $val);
    }
}

1;
