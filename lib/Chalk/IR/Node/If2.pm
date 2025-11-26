# ABOUTME: If node - conditional branch (v2 rewrite)
# ABOUTME: Control flow node that branches based on condition
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::If2 :isa(Chalk::IR::Node::Base2) {
    field $control :param :reader;    # Control predecessor node
    field $condition :param :reader;  # Condition node (boolean expression)
    field $id :reader = "if_" . $control->id . "_" . $condition->id;

    method op() { 'If' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'If',
            inputs => [$control->id, $condition->id],
            attributes => {
                control   => $control->id,
                condition => $condition->id,
            },
        };
    }
}

1;
