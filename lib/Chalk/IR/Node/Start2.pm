# ABOUTME: Start node - control flow entry point (v2 rewrite)
# ABOUTME: Has no control predecessor
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Start2 :isa(Chalk::IR::Node::Base2) {
    field $label :param :reader;
    field $id :reader = "start_${label}";

    method op() { 'Start' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Start',
            inputs => [],
            attributes => { label => $label },
        };
    }
}

1;
