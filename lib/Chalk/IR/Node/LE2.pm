# ABOUTME: LE node - binary less than or equal (v2 rewrite)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::LE2 :isa(Chalk::IR::Node::Base2) {
    field $left :param :reader;
    field $right :param :reader;
    field $id :reader = "le_" . $left->id . "_" . $right->id;

    method op() { 'LE' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'LE',
            inputs => [$left->id, $right->id],
            attributes => {
                left  => $left->id,
                right => $right->id,
            },
        };
    }
}

1;
