# ABOUTME: Allocates a new array in the heap and returns its heap ID
# ABOUTME: Supports fixed-length arrays with optional element type tracking
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::NewArray :isa(Chalk::IR::Node::Base) {
    field $length :param :reader = undef;           # NEW: size expression for fixed arrays
    field $element_type :param :reader = undef;     # NEW: element type for optimization

    method op() { 'NewArray' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NewArray',
            inputs => $self->inputs,
            attributes => {
                has_length => defined($length) ? 1 : 0,
                element_type => defined($element_type) ? $element_type->name : 'Any',
            },
        };
    }

    method execute($context) {
        # Allocate a new heap ID for this array
        my $env = $context->('env:');
        my $heap_id = $env->allocate_heap_id();

        # If length specified, store it in metadata
        if (defined($length)) {
            my $len_val = $context->("node:" . $length->id);
            $env->set_array_length($heap_id, $len_val);
        }

        return $heap_id;
    }

    method peephole($graph = undef) {
        return $self;
    }
}

1;
