# ABOUTME: CallEnd node for call completion projections
# ABOUTME: Sea of Nodes Chapter 18 - projects control, memory, and return value
use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Node::Proj;

class Chalk::IR::Node::CallEnd {
    field $call :param :reader;         # The Call node this completes
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    # Cached projection nodes
    field $_ctrl_proj = undef;
    field $_mem_proj = undef;
    field $_ret_proj = undef;

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method inputs() {
        my @inputs;
        push @inputs, $call->id if defined $call && $call->can('id');
        return \@inputs;
    }

    method op() { 'CallEnd' }

    method to_hash() {
        my $call_id = (defined $call && $call->can('id')) ? $call->id : undef;

        return {
            id     => $self->id,
            op     => 'CallEnd',
            inputs => $self->inputs,
            attributes => {
                call_id => $call_id,
            },
        };
    }

    method execute($context) {
        # CallEnd provides projections:
        # - Control: execution continues after call
        # - Memory: memory state after call
        # - Return value: the function's return value

        # Get the call node's evaluation result
        # In practice, this would coordinate with the function dispatch
        # For now, return undef as a placeholder
        return undef;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # CallEnd cannot be optimized away (side effect barrier)
        return $self;
    }

    method record_transform(@args) {
        return;
    }

    # Projection accessors for control, memory, and return value
    # Returns cached Proj nodes (created on first access)
    method ctrl_proj() {
        return $_ctrl_proj if defined $_ctrl_proj;
        $_ctrl_proj = Chalk::IR::Node::Proj->new(
            inputs => [ $self->id ],
            index  => 0,
            label  => 'ctrl',
            source => $self,
        );
        return $_ctrl_proj;
    }

    method mem_proj() {
        return $_mem_proj if defined $_mem_proj;
        $_mem_proj = Chalk::IR::Node::Proj->new(
            inputs => [ $self->id ],
            index  => 1,
            label  => 'mem',
            source => $self,
        );
        return $_mem_proj;
    }

    method ret_proj() {
        return $_ret_proj if defined $_ret_proj;
        $_ret_proj = Chalk::IR::Node::Proj->new(
            inputs => [ $self->id ],
            index  => 2,
            label  => 'ret',
            source => $self,
        );
        return $_ret_proj;
    }
}

1;
