# ABOUTME: TypeTuple represents multiple types for multi-return nodes
# ABOUTME: Used by Start to return (ctrl, arg) and similar patterns

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeTuple :isa(Chalk::IR::Type) {
    field $types :param :reader;  # ArrayRef of types

    method is_constant() {
        for my $t ($types->@*) {
            return 0 unless $t->is_constant;
        }
        return 1;
    }

    method value() {
        return [ map { $_->value } $types->@* ];
    }

    method at($index) {
        return $types->[$index];
    }

    sub of {
        my ($class, @types) = @_;
        return $class->new(types => \@types);
    }
}

1;
