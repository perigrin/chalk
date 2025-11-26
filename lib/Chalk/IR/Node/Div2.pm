# ABOUTME: Div node - binary division (v2 rewrite)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Div2 :isa(Chalk::IR::Node::Base2) {
    field $left :param :reader;
    field $right :param :reader;
    field $id :reader = "div_" . $left->id . "_" . $right->id;

    method op() { 'Div' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Div',
            inputs => [$left->id, $right->id],
            attributes => {
                left  => $left->id,
                right => $right->id,
            },
        };
    }
}

1;
