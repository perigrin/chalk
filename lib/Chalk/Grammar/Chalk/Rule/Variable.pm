# ABOUTME: Semantic action for Variable - looks up variable in scope or generates access nodes
# ABOUTME: Variable handles ScalarVar, ArrayVar, HashVar and subscripting ($arr[0], $hash{key})

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::ArrayGet;
use Chalk::IR::Node::HashGet;
# Note: blessed is auto-imported by use 5.42.0

class Chalk::Grammar::Chalk::Rule::Variable :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Variable -> ScalarVar (lookup variable in context)
        # Variable -> ArrayVar (lookup array in context)
        # Variable -> HashVar (lookup hash in context)
        # Variable -> ScalarVar '[' Expression ']' (array element access)
        # Variable -> ScalarVar '{' Expression '}' (hash element access)
        # Variable -> ArraySize (TODO)

        my @children = $context->children->@*;

        # Check for subscripting: ScalarVar '[' Expression ']' or ScalarVar '{' Expression '}'
        if (@children == 4) {
            my $child1 = $context->child(1);
            my $bracket = ref($child1) ? undef : $child1;

            if (defined($bracket) && ($bracket eq '[' || $bracket eq '{')) {
                return $self->_handle_subscript($context, $bracket);
            }
        }

        # Simple variable access (single child)
        return $self->_handle_simple_variable($context);
    }

    method _handle_subscript($context, $bracket) {
        my $var_metadata = $context->child(0);
        my $index_or_key = $context->child(2);  # The expression between brackets
        my $scope = $context->env->{scope};

        # Extract variable name from metadata
        my $var_name;
        if (ref($var_metadata) eq 'HASH' && $var_metadata->{type}) {
            $var_name = $var_metadata->{name};
        } else {
            die "Variable: expected variable metadata for subscript, got: " . (ref($var_metadata) || $var_metadata);
        }

        # Validate the index/key is an IR node
        unless (blessed($index_or_key) && $index_or_key->can('id')) {
            die "Variable: expected IR node for subscript index/key, got: " . (ref($index_or_key) || $index_or_key);
        }

        if ($bracket eq '[') {
            # Array element access: $arr[0]
            # Look up the array using @name
            my $array_node = $scope ? $scope->lookup('@' . $var_name) : undef;

            unless ($array_node && blessed($array_node) && $array_node->can('id')) {
                die "Variable: array '\@$var_name' not found in scope";
            }

            return Chalk::IR::Node::ArrayGet->new(
                inputs   => [],
                array_id => $array_node->id,
                index_id => $index_or_key->id,
            );
        } else {
            # Hash element access: $hash{key}
            # Look up the hash using %name
            my $hash_node = $scope ? $scope->lookup('%' . $var_name) : undef;

            unless ($hash_node && blessed($hash_node) && $hash_node->can('id')) {
                die "Variable: hash '\%$var_name' not found in scope";
            }

            return Chalk::IR::Node::HashGet->new(
                inputs  => [],
                hash_id => $hash_node->id,
                key_id  => $index_or_key->id,
            );
        }
    }

    method _handle_simple_variable($context) {
        # Get the variable metadata from child (ScalarVar, ArrayVar, or HashVar)
        my $var_metadata = $context->child(0);

        # Handle all variable types that return metadata hashes
        if (ref($var_metadata) eq 'HASH') {
            my $var_type = $var_metadata->{type} // '';
            my $var_name = $var_metadata->{name};
            my $sigil = $var_metadata->{sigil};
            my $scope = $context->env->{scope};

            # Construct the full variable name with sigil for scope lookup
            my $full_name = $sigil . $var_name;

            if ($var_type eq 'scalar_var' || $var_type eq 'array_var' || $var_type eq 'hash_var') {
                # Look up the variable's IR node from Scope
                # Scope stores actual node objects, not just IDs
                if ($scope) {
                    my $node = $scope->lookup($full_name);
                    if (defined($node) && ref($node) && $node->can('id')) {
                        # Return the node object directly
                        return $node;
                    }
                }

                # Not yet defined - return metadata (for VariableDeclaration to extract name)
                return $var_metadata;
            }
        }

        # For other variable types, pass through the metadata
        return $var_metadata;
    }

    # TypeInference semiring: infer types for variable access patterns
    # - Array dereference $x->[0] infers $x is ArrayRef
    # - Hash dereference $x->{key} infers $x is HashRef
    # - Array variable @arr adds @arr -> Array to type_env
    # - Hash variable %hash adds %hash -> Hash to type_env
    method infer_type($semiring, $element) {
        use Chalk::Grammar::Chalk::Type::ArrayRef;
        use Chalk::Grammar::Chalk::Type::HashRef;
        use Chalk::Grammar::Chalk::Type::Array;
        use Chalk::Grammar::Chalk::Type::Hash;

        my @children = $element->children->@*;
        my $type_env = { $element->type_env->%* };  # Clone existing type_env

        # Detect subscript/dereference patterns by scanning all tokens in the tree
        # Look for closing brackets ']' or '}' as the semiring stores the last matched token
        # Patterns:
        #   Direct:   ScalarVar '[' Expression ']' / ScalarVar '{' Expression '}'
        #   Arrow:    Variable '->' '[' Expression ']' / Variable '->' '{' Expression '}'
        my $is_array_subscript = 0;
        my $is_hash_subscript = 0;
        my $var_name;

        # Recursively collect all tokens to detect pattern
        my @all_tokens;
        $self->_collect_tokens($element, \@all_tokens);

        for my $token (@all_tokens) {
            my $val;

            # Extract value from token (either string or Token object)
            if (!ref($token)) {
                $val = $token;
            } elsif ($token->can('value')) {
                $val = $token->value;
            }

            next unless defined $val;

            # Look for closing brackets to detect subscript patterns
            if ($val eq ']') {
                $is_array_subscript = 1;
            } elsif ($val eq '}') {
                $is_hash_subscript = 1;
            }

            # Extract variable name (first non-bracket value)
            if (!defined $var_name && $val !~ /^[\[\]\{\}0-9]$/ && $val ne '->') {
                $var_name = $val;
            }
        }

        # For subscript/dereference access, infer the reference type
        if ($is_array_subscript && defined $var_name) {
            # $x[0] or $x->[0] implies $x is ArrayRef
            my $full_name = '$' . $var_name;
            $type_env->{$full_name} = Chalk::Grammar::Chalk::Type::ArrayRef->new();
        } elsif ($is_hash_subscript && defined $var_name) {
            # $x{key} or $x->{key} implies $x is HashRef
            my $full_name = '$' . $var_name;
            $type_env->{$full_name} = Chalk::Grammar::Chalk::Type::HashRef->new();
        }

        # Return element with updated type_env
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj  => $element->type_obj,  # Preserve the type
            type_env  => $type_env,
            children  => $element->children,
            token     => $element->token,
            errors    => $element->errors,
            start_pos => $element->start_pos,
            end_pos   => $element->end_pos,
            container_context => $element->container_context,
            value_context => $element->value_context
        );
    }

    # Helper to recursively collect all tokens from element tree
    method _collect_tokens($element, $tokens) {
        return unless defined $element;

        if ($element->can('token')) {
            my $token = $element->token;
            if (defined $token) {
                push $tokens->@*, $token;
            }
        }

        if ($element->can('children') && $element->children->@*) {
            for my $child ($element->children->@*) {
                $self->_collect_tokens($child, $tokens);
            }
        }
    }

    # Helper to recursively extract variable name from nested elements
    method _extract_var_name($element) {
        return undef unless defined $element;

        # Check if this element has a token with a variable name
        if ($element->can('token')) {
            my $token = $element->token;
            if (defined $token && ref($token) && $token->can('value')) {
                my $val = $token->value;
                if (defined $val && !ref($val)) {
                    return $val;
                }
            }
        }

        # Recursively check children
        if ($element->can('children')) {
            for my $child ($element->children->@*) {
                my $name = $self->_extract_var_name($child);
                return $name if defined $name;
            }
        }

        return undef;
    }
}

1;
