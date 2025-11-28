# ABOUTME: Semantic action for Assignment - binds variables to IR nodes using SSA
# ABOUTME: Assignment handles simple assignment (=) with direct data flow

use 5.42.0;
use experimental qw(class);

class Chalk::Grammar::Chalk::Rule::Assignment :isa(Chalk::GrammarRule) {
    use Chalk::IR::Node::Store;

    method evaluate($context) {
        # Assignment -> Ternary (pass-through)
        # Assignment -> Ternary WS_OPT '=' WS_OPT Assignment

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

        # Extract variable name from raw parse tree BEFORE semantic evaluation
        my $var_name;
        my $lhs_context = $context->children->[0];

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

        # If BFS didn't find scalar_var, check if LHS evaluates to a Proj node
        unless (defined($var_name)) {
            my $lhs = $context->child(0);
            if (blessed($lhs) && $lhs->can('op') && $lhs->op eq 'Proj') {
                $var_name = $lhs->label;
            }
        }

        unless (defined($var_name)) {
            return $context->child(0);
        }

        # Get right side (value to assign) - after '=' + WS_OPT
        my $rhs_index = $equals_index + 2;
        my $rhs = $context->child($rhs_index);

        # Validate we got an IR node for the value
        unless (blessed($rhs) && $rhs->can('id')) {
            return $context->child(0);
        }

        # Get current control from scope
        my $current_control = $scope->current_control;
        unless (defined($current_control)) {
            return $context->child(0);
        }

        # Create Store node directly (content-addressable ID)
        my $store = Chalk::IR::Node::Store->new(
            control => $current_control,
            var     => $var_name,
            value   => $rhs,
        );

        # Update scope immutably: create new scope with binding and control
        my $new_scope = $scope->with_binding($var_name, $rhs);
        $new_scope = $new_scope->with_control($store);

        # Update env's scope reference to the new immutable scope
        $context->env->{scope} = $new_scope;

        # Return Store node so control flow can be wired through it
        return $store;
    }
}

1;
