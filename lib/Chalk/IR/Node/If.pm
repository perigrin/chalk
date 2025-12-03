# ABOUTME: Conditional branch node in the IR graph
# ABOUTME: Represents if/then control flow split based on a boolean condition
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::If :isa(Chalk::IR::Node::Base) {
    use Chalk::IR::Type::Tuple;
    use Chalk::IR::Type::Ctrl;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Type::Bottom;

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

    # Type inference for If node
    # Returns TypeTuple with (true_branch_ctrl, false_branch_ctrl)
    # Uses dominator-based optimization to detect nested Ifs with identical predicates
    method compute() {
        # IF_BOTH: both branches reachable
        my $IF_BOTH = Chalk::IR::Type::Tuple->of(
            Chalk::IR::Type::Ctrl->CTRL(),
            Chalk::IR::Type::Ctrl->CTRL()
        );

        # IF_TRUE: only true branch reachable
        my $IF_TRUE = Chalk::IR::Type::Tuple->of(
            Chalk::IR::Type::Ctrl->CTRL(),
            Chalk::IR::Type::Bottom->BOTTOM()
        );

        # IF_FALSE: only false branch reachable
        my $IF_FALSE = Chalk::IR::Type::Tuple->of(
            Chalk::IR::Type::Bottom->BOTTOM(),
            Chalk::IR::Type::Ctrl->CTRL()
        );

        # Check if condition is constant
        if ($condition && $condition->can('compute')) {
            my $cond_type = $condition->compute();
            if ($cond_type->is_constant) {
                return $cond_type->value ? $IF_TRUE : $IF_FALSE;
            }
        }

        # Dominator-based optimization: walk up the dominator tree
        # looking for an If with identical predicate
        if ($control && $condition) {
            my $dom = $control;

            # Walk up the dominator tree
            while ($dom) {
                # Check if dom is a Proj from an If
                if ($dom->can('source') && $dom->source && $dom->source->op eq 'If') {
                    my $outer_if = $dom->source;

                    # Check if outer If has same predicate (same node object)
                    if ($outer_if->can('condition') && $outer_if->condition) {
                        if (refaddr($outer_if->condition) == refaddr($condition)) {
                            # Same predicate! Check which branch we're on
                            # index 0 = true branch, index 1 = false branch
                            my $proj_index = $dom->index;

                            if ($proj_index == 0) {
                                # We're on the TRUE branch of outer If
                                # So this inner If with same predicate is always true
                                return $IF_TRUE;
                            } else {
                                # We're on the FALSE branch of outer If
                                # So this inner If with same predicate is always false
                                return $IF_FALSE;
                            }
                        }
                    }
                }

                # Move up to parent dominator
                last unless $dom->can('idom');
                $dom = $dom->idom();
            }
        }

        # Default: both branches reachable
        return $IF_BOTH;
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
