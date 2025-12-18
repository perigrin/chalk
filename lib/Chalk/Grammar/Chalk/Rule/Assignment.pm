# ABOUTME: Semantic action for Assignment - binds variables to IR nodes using SSA
# ABOUTME: Assignment handles simple assignment (=) with direct data flow

use 5.42.0;
use experimental qw(class);
use Chalk::Grammar;  # Provides Chalk::GrammarRule base class
use Chalk::IR::Node::Store;

class Chalk::Grammar::Chalk::Rule::Assignment :isa(Chalk::GrammarRule) {

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

    # Type inference for TypeInference semiring
    # Extracts variable name from LHS and type from RHS, establishes binding
    method infer_type($semiring, $element) {
        # Element tree structure mirrors parse tree
        # Assignment has children built up through multiply() during parsing
        my @children = $element->children->@*;

        # Assignment variants:
        # - Assignment -> Ternary (pass-through, no binding) - few children
        # - Assignment -> Expression WS_OPT '=' WS_OPT Expression - 4+ children
        # - Assignment -> VariableDeclaration WS_OPT '=' WS_OPT Expression - 4+ children
        #
        # Note: The '=' terminal doesn't appear as a child element in TypeInference
        # because multiply() preserves it in the parent's token field, not as a child.
        # So we detect assignments by child count rather than looking for '=' token.
        return $element if scalar(@children) < 4;

        # Extract variable name from LHS (child 0) using BFS through parse tree
        # Look for BAREWORD_ANY or IDENTIFIER pattern tokens
        my $var_name;
        my @queue = ($children[0]);
        while (@queue && !defined($var_name)) {
            my $elem = shift @queue;
            next unless defined($elem);

            # Check if this element has a token with variable name
            if (defined $elem->token) {
                my $token = $elem->token;
                if ($token->can('pattern_name') && defined $token->pattern_name) {
                    my $pattern = $token->pattern_name;
                    # BAREWORD_ANY is used for variable names in scalar context
                    # IDENTIFIER is an alternative pattern name
                    if ($pattern eq 'BAREWORD_ANY' || $pattern eq 'IDENTIFIER') {
                        # Found variable name, prepend sigil
                        $var_name = '$' . $token->value;
                        last;
                    }
                }
            }

            # Continue BFS
            if (defined $elem->children) {
                push @queue, $elem->children->@*;
            }
        }

        # If we didn't find a variable name, just return element unchanged
        return $element unless defined($var_name);

        # Get RHS type from last child (the Expression after '=' WS_OPT)
        my $rhs_element = $children[-1];
        my $rhs_type = $rhs_element->type_obj;

        # Create new element with updated type_env
        my $new_type_env = { %{$element->type_env}, $var_name => $rhs_type };

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $element->type_obj,
            type_env => $new_type_env,
            children => $element->children,
            token => $element->token
        );
    }
}

1;
