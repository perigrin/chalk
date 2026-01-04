# ABOUTME: Semantic action for String - builds Constant IR node for string literals
# ABOUTME: Converts string literals to Constant nodes with type 'String'

use 5.42.0;
use experimental 'class';
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::IR::Node;

class Chalk::Grammar::Chalk::Rule::String :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # String -> DoubleQuotedString (may return IR node)
        # String -> SingleQuotedString (may return IR node)
        # String -> %VERSION% (version number like 5.42.0)
        # Child [0] contains either a token or an IR node

        my $child = $context->child(0);
        die "String: expected string token at child(0), got undefined - grammar bug" unless defined $child;

        # If child is already an IR node (from DoubleQuotedString/SingleQuotedString), pass through
        # This handles InterpolatedString nodes and Constant nodes from those rules
        # Check if it has an 'id' method which all IR nodes have
        if (ref($child) && $child->can('id')) {
            return $child;
        }

        # Otherwise, child is a token - strip quotes and create Constant
        my $value = "$child";
        if (length($value) >= 2 && $value =~ m/^['"]/) {
            $value = substr($value, 1, length($value) - 2);
        }

        # Create Constant node with proper Type object
        return Chalk::IR::Node::Constant->new(
            type  => Chalk::Grammar::Chalk::Type::Str->new(),
            value => $value,
        );
    }

    # Grammar type inference for field type narrowing
    # String literals always return Str type
    method grammar_type($context) {
        return Chalk::Grammar::Chalk::Type::Str->new();
    }

    # Type inference for TypeInference semiring
    # Returns element with Str type for string literals
    method infer_type($semiring, $element) {
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj  => Chalk::Grammar::Chalk::Type::Str->new(),
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
