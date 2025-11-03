# ABOUTME: Reference node in the IR graph
# ABOUTME: Represents reference operator (\$var) using context+label indirection model
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Reference :isa(Chalk::IR::Node::Base) {
    field $target_context :param :reader;  # Context to look in
    field $target_label :param :reader;    # Label to look up

    method op() { 'Reference' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Reference',
            inputs => $self->inputs,
            attributes => {
                target_context => $target_context,
                target_label => $target_label,
            },
        };
    }

    method execute($context) {
        # Reference stores a (context, label) pair
        # Return this as a reference object for dereferencing
        return {
            ref_type => 'SCALAR',
            ref_context => $target_context,
            ref_label => $target_label,
        };
    }
}

1;
