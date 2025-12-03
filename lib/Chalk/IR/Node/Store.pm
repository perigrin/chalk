# ABOUTME: Stores a value into a scalar variable
# ABOUTME: Represents variable assignment in Sea of Nodes IR with control + data edges
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Store {
    field $control :param :reader;
    field $var :param :reader;
    field $value :param :reader;
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
        return [ $control->id, $value->id ];
    }

    method op() { 'Store' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Store',
            inputs => $self->inputs,
            attributes => {
                var        => $var,
                control_id => $control->id,
                value_id   => $value->id,
            },
        };
    }

    method execute($context) {
        # Get the value to store
        my $val = $context->("node:" . $value->id);

        # Store in scope/context (implementation depends on runtime)
        # For now, just return the value (assignment evaluates to assigned value)
        return $val;
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    # Stub for transform tracking (not used in v2 but called by Builder)
    method record_transform(@args) {
        # No-op for compatibility
        return;
    }


    # Immutable reconstruction with new control edge
    method with_control($new_control) {
        return Chalk::IR::Node::Store->new(
            var     => $self->var,
            value   => $self->value,
            control => $new_control,
        );
    }
}

1;
