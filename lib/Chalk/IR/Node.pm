# ABOUTME: Sea of Nodes IR node representation for Chalk compiler
# ABOUTME: Represents a single node in the IR graph with operation type, inputs, and attributes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Node {
    field $id           :param :reader;
    field $op           :param :reader;
    field $inputs       :param :reader;
    field $attributes   :param :reader;

    method to_hash() {
        return {
            id           => $id,
            op           => $op,
            inputs       => $inputs,
            attributes   => $attributes,
        };
    }
}

1;
