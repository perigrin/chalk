# ABOUTME: Metadata struct for a class declaration.
# ABOUTME: Stores name, parent, fields, methods, subs, and all body items in order.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::ClassInfo {
    field $name    :param :reader;
    field $parent  :param :reader = undef;
    field $fields  :param :reader = [];
    field $methods :param :reader = [];
    field $subs    :param :reader = [];
    field $body    :param :reader = [];

    # Content-based ID for use in NodeFactory hash-cons keys.
    # ClassInfo objects may appear as inputs inside hash-consed nodes,
    # so they must be addressable by id.
    method id() {
        my $parent_str = defined $parent ? $parent : 'undef';
        my $fields_str = join(',', map { $_->id() } $fields->@*);
        my $methods_str = join(',', map { $_->id() } $methods->@*);
        my $subs_str = join(',', map { $_->id() } $subs->@*);
        return "ClassInfo:$name:$parent_str:[$fields_str]:[$methods_str]:[$subs_str]";
    }

    # No-op: ClassInfo does not participate in the use-def chain.
    method add_consumer($consumer) {
        return;
    }
}
