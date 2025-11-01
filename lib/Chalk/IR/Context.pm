# ABOUTME: Context-as-closure abstraction for unified memory model
# ABOUTME: Implements functional closures for context extension and lookup operations
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Context {
    # Returns base closure that returns undef for any label
    sub empty_context($class) {
        return sub ($label) {
            return undef;
        };
    }

    # Creates new context extending parent with label->value binding
    sub extend_context($class, $parent, $label, $value) {
        return sub ($lookup_label) {
            return $value if $lookup_label eq $label;
            return $parent->($lookup_label);
        };
    }

    # Creates a namespaced label to prevent collisions (e.g., "var:x", "temp:t1")
    sub make_label($class, $namespace, $name) {
        return "${namespace}:${name}";
    }
}

1;
