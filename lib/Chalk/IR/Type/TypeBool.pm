# ABOUTME: TypeBool represents a constant boolean value in IR
# ABOUTME: Uses builtin::true/builtin::false for native Perl booleans

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeBool :isa(Chalk::IR::Type) {
    field $value :param :reader;

    method is_constant() { return 1; }

    sub TRUE {
        state $singleton = __PACKAGE__->new(value => true);
        return $singleton;
    }

    sub FALSE {
        state $singleton = __PACKAGE__->new(value => false);
        return $singleton;
    }

    sub constant {
        my ($class, $val) = @_;
        return $val ? $class->TRUE : $class->FALSE;
    }
}

1;
