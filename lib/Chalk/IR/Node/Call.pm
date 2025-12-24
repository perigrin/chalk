# ABOUTME: Call node for function/method invocation
# ABOUTME: Sea of Nodes Chapter 18 - simplified implementation for Chalk
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Call {
    field $callee :param :reader;       # Function name node or expression
    field $args :param :reader = [];    # Argument IR nodes
    field $receiver :param :reader = undef;  # For method calls, the object/class
    field $rpc :reader;                 # Return program counter (call-site ID)
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Class-level RPC counter for unique call-site IDs
    my $rpc_counter = 0;

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    ADJUST {
        # Generate unique RPC for this call site
        $rpc = 'rpc_' . $rpc_counter++;
    }

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method inputs() {
        my @inputs;
        push @inputs, $callee->id if defined $callee && $callee->can('id');
        push @inputs, $receiver->id if defined $receiver && $receiver->can('id');
        for my $arg ($args->@*) {
            push @inputs, $arg->id if defined $arg && $arg->can('id');
        }
        return \@inputs;
    }

    method op() { 'Call' }

    method to_hash() {
        my $callee_id = (defined $callee && $callee->can('id')) ? $callee->id : undef;
        my $receiver_id = (defined $receiver && $receiver->can('id')) ? $receiver->id : undef;
        my @arg_ids = map { $_->id } grep { defined $_ && $_->can('id') } $args->@*;

        return {
            id     => $self->id,
            op     => 'Call',
            inputs => $self->inputs,
            attributes => {
                callee_id   => $callee_id,
                receiver_id => $receiver_id,
                arg_ids     => \@arg_ids,
                rpc         => $rpc,
            },
        };
    }

    method execute($context) {
        # Get the callee (function name or reference)
        my $func_name = $context->("node:" . $callee->id);

        # Get evaluated arguments
        my @evaluated_args;
        for my $arg ($args->@*) {
            push @evaluated_args, $context->("node:" . $arg->id);
        }

        # For method calls, get receiver
        my $recv_value;
        if (defined $receiver) {
            $recv_value = $context->("node:" . $receiver->id);
        }

        # Return call descriptor for CallEnd to process
        # This contains all information needed for function dispatch
        my $descriptor = {
            func_name => $func_name,
            args      => \@evaluated_args,
            rpc       => $rpc,
        };

        # Include receiver for method calls
        if (defined $recv_value) {
            $descriptor->{receiver} = $recv_value;
        }

        return $descriptor;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # Calls cannot be constant-folded (side effects)
        return $self;
    }

    method record_transform(@args) {
        return;
    }

    # Clone with new inputs from node_map, preserving polymorphic Call type
    # Used by GVN optimizer to reconstruct nodes
    # $node_map is old_id -> new_node mapping
    method clone_with_inputs($new_inputs, $node_map, $new_attributes = {}) {
        my $new_callee;
        my $new_receiver;
        my @new_args;

        # Reconstruct field references from new_inputs array
        # Input order: callee, receiver (if present), args...
        my $idx = 0;

        # First input is always callee (if it exists)
        if (defined $new_inputs->[$idx] && exists $node_map->{$new_inputs->[$idx]}) {
            $new_callee = $node_map->{$new_inputs->[$idx]};
            $idx++;
        }

        # Second input is receiver (if original had one)
        if (defined $receiver) {
            if (defined $new_inputs->[$idx] && exists $node_map->{$new_inputs->[$idx]}) {
                $new_receiver = $node_map->{$new_inputs->[$idx]};
                $idx++;
            }
        }

        # Remaining inputs are args
        while ($idx < scalar($new_inputs->@*)) {
            if (defined $new_inputs->[$idx] && exists $node_map->{$new_inputs->[$idx]}) {
                push @new_args, $node_map->{$new_inputs->[$idx]};
            }
            $idx++;
        }

        return Chalk::IR::Node::Call->new(
            callee      => $new_callee,
            args        => \@new_args,
            receiver    => $new_receiver,
            source_info => $source_info,
        );
    }
}

1;
