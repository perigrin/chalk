# ABOUTME: Panic node terminates execution with a runtime error
# ABOUTME: Used for bounds checking violations and other unrecoverable errors
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Panic :isa(Chalk::IR::Node::Base) {
    field $message :param :reader;

    method op() { 'Panic' }

    method to_hash() {
        return {
            id => $self->id,
            op => 'Panic',
            inputs => $self->inputs,
            attributes => {
                message => $message,
                source_info => $self->source_info,
            },
        };
    }

    method execute($context) {
        # Terminate execution with error
        die "PANIC: $message";
    }

    method peephole($graph = undef) {
        return $self;  # Cannot optimize away panic
    }

    # Panic is a control flow terminator like Never
    method is_terminator() { 1 }
}

1;
