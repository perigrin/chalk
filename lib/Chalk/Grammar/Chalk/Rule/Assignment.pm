# ABOUTME: Semantic action for Assignment - binds variables to IR nodes using SSA
# ABOUTME: Returns RHS value for expression chaining, updates Scope with binding

use 5.42.0;
use experimental qw(class);
use Chalk::Grammar;  # Provides Chalk::GrammarRule base class

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

        # Extract variable name from evaluated LHS
        # Load, UnboundVariable, and Proj all have name() or label()
        my $lhs = $context->child(0);
        my $var_name;

        if ($lhs && $lhs->can('name')) {
            $var_name = $lhs->name;
        } elsif ($lhs && $lhs->can('label')) {
            # Proj node uses label() instead of name()
            $var_name = $lhs->label;
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

        # Update scope immutably: create new scope with binding to RHS value
        # In SSA, assignments are expressions that return values, not statements with Store nodes
        # Store nodes are only for memory (heap) operations, not variable bindings
        my $new_scope = $scope->with_binding($var_name, $rhs);

        # Update env's scope reference to the new immutable scope
        $context->env->{scope} = $new_scope;

        # Return RHS value (enables expression chaining: my $foo = my $bar = 5)
        return $rhs;
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
            token => $element->token,
            errors => $element->errors,
            start_pos => $element->start_pos,
            end_pos => $element->end_pos,
            container_context => $element->container_context,
            value_context => $element->value_context
        );
    }
}

1;
