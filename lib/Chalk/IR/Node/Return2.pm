# ABOUTME: Return node - control flow exit (v2 rewrite)
# ABOUTME: Has control predecessor and value reference
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Return2 :isa(Chalk::IR::Node::Base2) {
    field $control :param :reader;
    field $value :param :reader;
    field $id :reader = "return_" . $control->id . "_" . $value->id;

    method op() { 'Return' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Return',
            inputs => [$control->id, $value->id],
            attributes => {
                control  => $control->id,
                value_id => $value->id,
            },
        };
    }
}

1;
