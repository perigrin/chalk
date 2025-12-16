# ABOUTME: Die node representing exception throw in the IR graph
# ABOUTME: Terminates control flow abnormally with an error message
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Die :isa(Chalk::IR::Node::CFGNode) {

    field $control :param :reader;
    field $message :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    # Compute inputs from child nodes
    method inputs() {
        my @inputs;
        push @inputs, $control->id if defined $control && $control->can('id');
        push @inputs, $message->id if defined $message && $message->can('id');
        return \@inputs;
    }

    method op() { 'Die' }

    method to_hash() {
        my $ctrl_id = (defined $control && $control->can('id')) ? $control->id : undef;
        my $msg_id = (defined $message && $message->can('id')) ? $message->id : undef;
        return {
            id     => $self->id,
            op     => 'Die',
            inputs => $self->inputs,
            attributes => {
                control    => $ctrl_id,
                control_id => $ctrl_id,
                message_id => $msg_id,
            },
        };
    }

    method execute($context) {
        # Die terminates execution with an exception
        return undef unless defined $control && $control->can('id');

        # Check if this Die's control path is active
        my $control_active = $context->("node:" . $control->id);

        # Skip execution if control is explicitly 0 (inactive path)
        return undef if (defined($control_active) && $control_active == 0);

        # Get the error message from context
        my $error_msg = "Unimplemented";
        if (defined $message && $message->can('id')) {
            $error_msg = $context->("node:" . $message->id) // "Unimplemented";
        }

        die $error_msg;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }

    # Immutable reconstruction with new control edge
    method with_control($new_control) {
        return Chalk::IR::Node::Die->new(
            message => $message,
            control => $new_control,
        );
    }

    # Dominator tree: Die's immediate dominator is its control input
    method idom() {
        return $control;
    }

    # Dominator depth: cached computation based on idom chain
    field $_idepth = undef;
    method idepth() {
        return $_idepth if defined $_idepth;

        my $idom = $self->idom;
        if (!defined $idom) {
            $_idepth = 0;
        } elsif ($idom->can('idepth')) {
            $_idepth = $idom->idepth + 1;
        } else {
            $_idepth = 1;
        }

        return $_idepth;
    }

    # Dominator check: walk up idom chain from $other to see if we reach $self
    method dominates($other) {
        return 1 if refaddr($self) == refaddr($other);

        my $current = $other;
        while (defined $current && $current->can('idom')) {
            my $idom = $current->idom;
            last unless defined $idom;

            return 1 if refaddr($self) == refaddr($idom);
            $current = $idom;
        }

        return 0;
    }
}

1;
