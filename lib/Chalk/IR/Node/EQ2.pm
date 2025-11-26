# ABOUTME: EQ node - binary equals (v2 rewrite)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::EQ2 :isa(Chalk::IR::Node::Base2) {
    field $left :param :reader;
    field $right :param :reader;
    field $id :reader = "eq_" . $left->id . "_" . $right->id;

    method op() { 'EQ' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'EQ',
            inputs => [$left->id, $right->id],
            attributes => {
                left  => $left->id,
                right => $right->id,
            },
        };
    }
}

1;
