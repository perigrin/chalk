# ABOUTME: Semantic action for ReferenceConstructor - array and hash constructors
# ABOUTME: Builds IR nodes for anonymous array and hash references

use 5.42.0;
use experimental 'class';
use Chalk::Grammar::Chalk::Type::ArrayRef;
use Chalk::Grammar::Chalk::Type::HashRef;
use Chalk::Grammar::Chalk::Type::Any;

class Chalk::Grammar::Chalk::Rule::ReferenceConstructor :isa(Chalk::GrammarRule) {
    

    method evaluate($context) {
        # ReferenceConstructor -> '[' WS_OPT ExpressionList WS_OPT ']'  # Array constructor
        # ReferenceConstructor -> '[' WS_OPT ']'  # Empty array
        # ReferenceConstructor -> '{' WS_OPT ExpressionList WS_OPT '}'  # Hash constructor
        # ReferenceConstructor -> '{' WS_OPT '}'  # Empty hash

        # Get first child to determine bracket type
        my $first_child = $context->child(0);
        die "ReferenceConstructor: expected bracket token at child(0), got undefined - grammar bug" unless defined $first_child;

        my $bracket = "$first_child";  # Stringify Token

        if ($bracket eq '[') {
            # Array constructor
            my $node_id = "array_new";
            my $array_node = Chalk::IR::Node::NewArray->new(
                id     => $node_id,
                inputs => [],
            );

            # Find and push elements if present
            my @children = $context->children->@*;
            for my $i (1 .. $#children - 1) {
                my $child = $context->child($i);
                next unless defined $child;
                # Skip non-IR nodes (whitespace, commas, etc)
                if (ref($child) && $child->can('id')) {
                    my $array_ref = { op => 'NodeRef', node_id => $array_node->id };
                    my $value_ref = { op => 'NodeRef', node_id => $child->id };
                    my $attributes = {
                        array => $array_ref,
                        value => $value_ref
                    };
                    my $push_id = "array_push_" . $array_node->id . "_" . $child->id;
                    my $array_push = Chalk::IR::Node->new(
                        id     => $push_id,
                        op     => 'ArrayPush',
                        inputs => [ $array_node->id, $child->id ],
                        attributes => $attributes,
                    );
                    # Update the array node reference to the last push operation
                    # This creates a chain of operations
                    $array_node = $array_push;
                }
            }

            return $array_node;
        }
        elsif ($bracket eq '{') {
            # Hash constructor
            my $node_id = "hash_new";
            my $hash_node = Chalk::IR::Node::NewHash->new(
                id     => $node_id,
                inputs => [],
            );

            # Find key-value pairs and set them
            my @children = $context->children->@*;
            my @ir_nodes;
            for my $i (1 .. $#children - 1) {
                my $child = $context->child($i);
                next unless defined $child;
                if (ref($child) && $child->can('id')) {
                    push @ir_nodes, $child;
                }
            }

            # Hash elements come in key => value pairs
            while (@ir_nodes >= 2) {
                my $key = shift @ir_nodes;
                my $value = shift @ir_nodes;
                my $set_id = "hash_set_" . $hash_node->id . "_" . $key->id . "_" . $value->id;
                my $hash_set = Chalk::IR::Node::HashSet->new(
                    id       => $set_id,
                    inputs   => [ $hash_node->id, $key->id, $value->id ],
                    hash_id  => $hash_node->id,
                    key_id   => $key->id,
                    value_id => $value->id,
                );
                # Update hash node reference to the last set operation
                $hash_node = $hash_set;
            }

            return $hash_node;
        }

        die "ReferenceConstructor: expected '[' or '{' bracket, got '$bracket' - grammar bug";
    }

    # Grammar type inference for field type narrowing
    # Returns ArrayRef for [] and HashRef for {}
    method grammar_type($context) {
        my $first_child = $context->child(0);
        return Chalk::Grammar::Chalk::Type::Any->new() unless defined $first_child;

        my $bracket = "$first_child";
        if ($bracket eq '[') {
            return Chalk::Grammar::Chalk::Type::ArrayRef->new();
        }
        elsif ($bracket eq '{') {
            return Chalk::Grammar::Chalk::Type::HashRef->new();
        }

        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    # Type inference for TypeInference semiring
    # Returns element with ArrayRef or HashRef type based on bracket
    method infer_type($semiring, $element) {
        # Determine bracket type from element token or children
        # For empty constructors [], the element may have token=']' with no children
        # For constructors with content, children include the opening bracket
        my $bracket;

        # First check children for opening bracket
        my @children = $element->children->@*;
        for my $child (@children) {
            if ($child->can('token') && defined $child->token) {
                my $val = $child->token->value // '';
                if ($val eq '[' || $val eq '{') {
                    $bracket = $val;
                    last;
                }
            }
        }

        # If not found in children, infer from closing bracket in element's token
        unless (defined $bracket) {
            if ($element->can('token') && defined $element->token) {
                my $tok_val = $element->token->value // '';
                if ($tok_val eq ']') {
                    $bracket = '[';  # Closing ] means array
                }
                elsif ($tok_val eq '}') {
                    $bracket = '{';  # Closing } means hash
                }
            }
        }

        my $type_obj;
        if (defined $bracket && $bracket eq '[') {
            $type_obj = Chalk::Grammar::Chalk::Type::ArrayRef->new();
        }
        elsif (defined $bracket && $bracket eq '{') {
            $type_obj = Chalk::Grammar::Chalk::Type::HashRef->new();
        }
        else {
            $type_obj = Chalk::Grammar::Chalk::Type::Any->new();
        }

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj  => $type_obj,
            type_env  => $element->type_env,
            children  => $element->children,
            token     => $element->token,
            errors    => $element->errors,
            start_pos => $element->start_pos,
            end_pos   => $element->end_pos,
            container_context => $element->container_context,
            value_context => $element->value_context
        );
    }
}

1;
