# ABOUTME: Semantic action for Assignment (v2 rewrite)
# ABOUTME: Creates Store2 nodes directly without Builder
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Assignment2 {
    use Chalk::IR::Node::Store2;
    use Scalar::Util qw(blessed);

    method evaluate($context) {
        # Assignment -> Ternary (pass-through)
        # Assignment -> Ternary '=' Assignment

        my @children = $context->children->@*;

        # Check if this is an assignment operation (has '=' operator)
        my $has_assignment = 0;
        my $equals_index = -1;
        for my $i (0..$#children) {
            my $child = $children[$i];
            # Handle both direct strings and context objects
            my $extracted = $child;
            if (blessed($child) && $child->can('extract')) {
                $extracted = $child->extract;
            }
            if (defined($extracted) && "$extracted" eq '=') {
                $has_assignment = 1;
                $equals_index = $i;
                last;
            }
        }

        # If no '=' operator, just pass through the Ternary child
        return $context->child(0) unless $has_assignment;

        # Get scope from environment
        my $scope = $context->env->{scope};
        return $context->child(0) unless $scope;

        # Extract variable name from LHS parse tree BEFORE semantic evaluation
        # We need the raw variable name, not an evaluated IR node
        my $var_name;
        my $lhs_context = $children[0];

        # Breadth-first search through parse tree for scalar_var metadata
        my @queue = ($lhs_context);
        while (@queue && !defined($var_name)) {
            my $ctx = shift @queue;
            next unless defined($ctx);

            if (blessed($ctx) && $ctx->can('extract')) {
                my $val = $ctx->extract;
                if (ref($val) eq 'HASH' && $val->{type} && $val->{type} eq 'scalar_var') {
                    $var_name = $val->{name};
                    last;
                }
            }

            if (blessed($ctx) && $ctx->can('children')) {
                push @queue, $ctx->children->@*;
            }
        }

        unless (defined($var_name)) {
            # Couldn't find variable name - not a valid assignment target
            return $context->child(0);
        }

        # Get right side (value to assign)
        # After '=' which is at equals_index
        my $rhs_index = $equals_index + 1;
        my $rhs = $context->child($rhs_index);

        # Validate we got an IR node for the value
        unless (blessed($rhs) && $rhs->can('id')) {
            return $context->child(0);
        }

        # Get current control from scope
        my $current_control = $scope->current_control;
        unless (defined($current_control)) {
            # No control node available - can't create Store
            return $context->child(0);
        }

        # Create Store2 node
        my $store = Chalk::IR::Node::Store2->new(
            control => $current_control,
            var     => $var_name,
            value   => $rhs,
        );

        # Update scope with new binding
        $scope->define($var_name, $rhs);

        # Update current_control to the Store node
        $scope->set_current_control($store);

        # Return Store node
        return $store;
    }
}

1;
