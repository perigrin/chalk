# ABOUTME: Metadata struct for a class field declaration.
# ABOUTME: Stores name, attributes (param/reader/writer), and optional default value.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::FieldInfo {
    field $name          :param :reader;
    field $attributes    :param :reader = [];
    field $default_value :param :reader = undef;

    # Content-based ID for use in NodeFactory hash-cons keys.
    # FieldInfo objects may appear as inputs inside hash-consed Constructor nodes
    # (e.g., ClassDecl body), so they must be addressable by id.
    method id() {
        my $attrs_str = join(',', map {
            my $attr = $_;
            ref($attr) eq 'HASH'
                ? join(';', map { "$_=" . ($attr->{$_} // 'undef') } sort keys %$attr)
                : (defined $attr ? "$attr" : 'undef')
        } $attributes->@*);
        my $default_str = defined $default_value
            ? (ref($default_value) && $default_value->can('id')
                ? $default_value->id()
                : "$default_value")
            : 'undef';
        return "FieldInfo:$name:[$attrs_str]:$default_str";
    }

    # No-op: FieldInfo does not participate in the use-def chain.
    method add_consumer($consumer) {
        return;
    }
}
