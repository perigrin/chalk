# ABOUTME: Metadata struct for a use declaration.
# ABOUTME: Stores module name as a string and import arguments as an arrayref.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::UseInfo {
    field $name    :param :reader;
    field $args    :param :reader = [];
    field $keyword :param :reader = 'use';

    # Content-based ID for use in NodeFactory hash-cons keys.
    # UseInfo objects are not hash-consed themselves, but may appear as inputs
    # inside hash-consed Constructor nodes (e.g., Program statements).
    method id() {
        my $args_str = join(',', map { ref($_) ? (defined($_->can('value')) ? $_->value() : ref($_)) : ($_ // 'undef') } $args->@*);
        return "UseInfo:$name:[$args_str]";
    }

    # No-op: UseInfo does not participate in the use-def chain.
    method add_consumer($consumer) {
        return;
    }
}
