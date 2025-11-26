# ABOUTME: Base class for simplified IR nodes (v2 rewrite)
# ABOUTME: Provides common infrastructure - ID, inputs, serialization
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Base2 {
    field $inputs :param :reader = [];

    method to_hash() {
        return {
            id     => $self->id,
            inputs => $inputs,
        };
    }
}

1;
