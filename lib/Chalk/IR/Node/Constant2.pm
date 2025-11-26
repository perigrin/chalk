# ABOUTME: Constant node for literal values (v2 rewrite)
# ABOUTME: Content-addressable ID computed from type and value
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Constant2 :isa(Chalk::IR::Node::Base2) {
    field $type :param :reader;
    field $value :param :reader;
    field $id :reader = "const_${type}_${value}";

    method op() { 'Constant' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Constant',
            inputs => [],
            attributes => {
                type  => $type,
                value => $value,
            },
        };
    }
}

1;
