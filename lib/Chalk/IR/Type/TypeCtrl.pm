# ABOUTME: TypeCtrl represents a control token in IR
# ABOUTME: Singleton type for control flow (has no data value)

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeCtrl :isa(Chalk::IR::Type) {
    method is_constant() { return 1; }
    method value() { return undef; }

    sub CTRL {
        state $singleton = __PACKAGE__->new();
        return $singleton;
    }
}

1;
