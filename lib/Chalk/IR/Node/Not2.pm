# ABOUTME: Not node - logical negation (v2 rewrite)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Not2 :isa(Chalk::IR::Node::Base2) {
    field $operand :param :reader;
    field $id :reader = "not_" . $operand->id;

    method op() { 'Not' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Not',
            inputs => [$operand->id],
            attributes => {
                operand => $operand->id,
            },
        };
    }
}

1;
