# ABOUTME: Semantic action for String - builds Constant IR node for string literals
# ABOUTME: Converts string literals to Constant nodes with type 'String'

use 5.42.0;
use experimental 'class';
use Scalar::Util qw(blessed);
use Chalk::Grammar::Chalk::Type::Str;

class Chalk::Grammar::Chalk::Rule::String :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # String -> %STRING%  (double-quoted string literal)
        # String -> %SQSTRING%  (single-quoted string literal)
        # String -> %VERSION% (version number like 5.42.0)
        # Child [0] contains the matched string literal with quotes

        my $child_value = $context->child(0);
        die "String: expected string token at child(0), got undefined - grammar bug" unless defined $child_value;

        # If child already evaluated to Constant, pass through
        # (SingleQuotedString/DoubleQuotedString already create proper Constants)
        if (blessed($child_value) && $child_value->can('op') && $child_value->op eq 'Constant') {
            return $child_value;
        }

        # Otherwise, create Constant (for VERSION tokens that come directly)
        my $value = "$child_value";
        # Strip quotes if present
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
