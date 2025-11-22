# ABOUTME: Semantic action for ReferenceConstructor - array and hash constructors
# ABOUTME: Builds IR nodes for anonymous array and hash references

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ReferenceConstructor :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ReferenceConstructor -> '[' WS_OPT ExpressionList WS_OPT ']'  # Array constructor
        # ReferenceConstructor -> '[' WS_OPT ']'  # Empty array
        # ReferenceConstructor -> '{' WS_OPT ExpressionList WS_OPT '}'  # Hash constructor
        # ReferenceConstructor -> '{' WS_OPT '}'  # Empty hash

        my $builder = $context->env->{ir_builder};
        return $context->child(0) unless $builder;

        # Get first child to determine bracket type
        my $first_child = $context->child(0);
        return $first_child unless defined $first_child;

        my $bracket = "$first_child";  # Stringify Token

        if ($bracket eq '[') {
            # Array constructor
            my $array_node = $builder->build_array_new_node();

            # Find and push elements if present
            my @children = $context->children->@*;
            for my $i (1 .. $#children - 1) {
                my $child = $context->child($i);
                next unless defined $child;
                # Skip non-IR nodes (whitespace, commas, etc)
                if (ref($child) && $child isa Chalk::IR::Node::Base) {
                    $builder->build_array_push_node($array_node, $child);
                }
            }

            return $array_node;
        }
        elsif ($bracket eq '{') {
            # Hash constructor
            my $hash_node = $builder->build_hash_new_node();

            # Find key-value pairs and set them
            my @children = $context->children->@*;
            my @ir_nodes;
            for my $i (1 .. $#children - 1) {
                my $child = $context->child($i);
                next unless defined $child;
                if (ref($child) && $child isa Chalk::IR::Node::Base) {
                    push @ir_nodes, $child;
                }
            }

            # Hash elements come in key => value pairs
            while (@ir_nodes >= 2) {
                my $key = shift @ir_nodes;
                my $value = shift @ir_nodes;
                $builder->build_hash_set_node($hash_node, $key, $value);
            }

            return $hash_node;
        }

        return $first_child;
    }
}

1;
