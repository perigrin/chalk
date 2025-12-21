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
}

1;
