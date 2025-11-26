# ABOUTME: Negate node - unary negation (v2 rewrite)
# ABOUTME: Pure data node, no control edges
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Negate2 :isa(Chalk::IR::Node::Base2) {
    field $operand :param :reader;
    field $id :reader = "negate_" . $operand->id;

    method op() { 'Negate' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Negate',
            inputs => [$operand->id],
            attributes => {
                operand => $operand->id,
            },
        };
    }
}

1;
