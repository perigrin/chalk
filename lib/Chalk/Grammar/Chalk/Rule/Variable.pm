# ABOUTME: Semantic action for Variable - looks up variable in scope or generates access nodes
# ABOUTME: Variable handles ScalarVar, ArrayVar, HashVar and subscripting ($arr[0], $hash{key})

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::ArrayGet;
use Chalk::IR::Node::HashGet;
use Scalar::Util 'blessed';

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
}

1;
