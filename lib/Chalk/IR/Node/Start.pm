# ABOUTME: Start node representing function entry point in the IR graph
# ABOUTME: Defines the initial control and data state for a function
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Start :isa(Chalk::IR::Node::Base) {
    field $function_name :param :reader;
    field $params        :param :reader;

    method op() { 'Start' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Start',
            inputs => $self->inputs,
            attributes => {
                function_name => $function_name,
                params        => $params,
            },
        };
    }

    method execute() {
        # Start node returns a control token (undef for now)
        return undef;
    }
}

1;
