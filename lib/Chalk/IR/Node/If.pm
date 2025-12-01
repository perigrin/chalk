# ABOUTME: Conditional branch node in the IR graph
# ABOUTME: Represents if/then control flow split based on a boolean condition
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::If :isa(Chalk::IR::Node::Base) {
    field $condition_id :param :reader;
    # Object reference to condition node for graph traversal
    field $condition :param :reader = undef;
    # Object reference to control input for graph traversal
    # This enables BFS to find the Start/Store node that controls this If
    field $control :param :reader = undef;

    method op() { 'If' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'If',
            inputs => $self->inputs,
            attributes => {
                condition_id => $condition_id,
            },
        };
    }

    method execute($context) {
        # If node returns the condition value (1 or 0)
        # This tells Proj nodes which path is active
        return $context->("node:$condition_id");
    }

    # Peephole optimization for If nodes
    # If condition is constant, this helps Proj nodes detect dead branches
    method peephole($graph = undef) {
        return $self unless $graph;

        # Check if condition is a constant
        my $cond_node = $condition // ($graph ? $graph->get_node($condition_id) : undef);
        return $self unless $cond_node;

        # If condition is constant, we can optimize
        # But the If node itself doesn't change - Proj nodes will detect the dead branch
        return $self;
    }

    # Check if the condition is a known constant value
    # Returns (is_constant, value) where value is the boolean result
    method is_constant_condition($graph) {
        return (0, undef) unless $graph;

        my $cond_node = $condition // $graph->get_node($condition_id);
        return (0, undef) unless $cond_node;

        # Check if condition node is a Constant
        if ($cond_node->op eq 'Constant') {
            my $value = $cond_node->attributes->{value} // $cond_node->value;
            # Convert to boolean: 0 is false, anything else is true
            my $bool_value = $value ? 1 : 0;
            return (1, $bool_value);
        }

        return (0, undef);
    }
}

1;
