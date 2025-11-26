# ABOUTME: Store node - variable assignment (v2 rewrite)
# ABOUTME: Control node that sits in control chain, carries value reference
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Store2 :isa(Chalk::IR::Node::Base2) {
    field $control :param :reader;
    field $var :param :reader;
    field $value :param :reader;
    field $id :reader = "store_${var}_" . $control->id . "_" . $value->id;

    method op() { 'Store' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Store',
            inputs => [$control->id, $value->id],
            attributes => {
                var      => $var,
                control  => $control->id,
                value_id => $value->id,
            },
        };
    }
}

1;
