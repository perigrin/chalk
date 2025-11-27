# ABOUTME: Semantic action for ReferenceConstructor - array and hash constructors
# ABOUTME: Builds IR nodes for anonymous array and hash references

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ReferenceConstructor :isa(Chalk::GrammarRule) {
    use Chalk::IR::Node::NewArray;
    use Chalk::IR::Node::NewHash;
    use Chalk::IR::Node::HashSet;
    use Chalk::IR::Node;
    use Scalar::Util qw(blessed);

    method evaluate($context) {
        # ReferenceConstructor -> '[' WS_OPT ExpressionList WS_OPT ']'  # Array constructor
        # ReferenceConstructor -> '[' WS_OPT ']'  # Empty array
        # ReferenceConstructor -> '{' WS_OPT ExpressionList WS_OPT '}'  # Hash constructor
        # ReferenceConstructor -> '{' WS_OPT '}'  # Empty hash

        # Get first child to determine bracket type
        my $first_child = $context->child(0);
        return $first_child unless defined $first_child;

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

        return $first_child;
    }
}

1;
