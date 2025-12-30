# ABOUTME: Semantic action for Literal - pass through child value from specific literal type
# ABOUTME: Literal delegates to Number, String, etc. which build their own IR nodes

use 5.42.0;
use experimental 'class';

use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Undef;
use Chalk::Grammar::Chalk::Type::Boolean;

class Chalk::Grammar::Chalk::Rule::Literal :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Literal -> Number (Number builds Constant node)
        # Literal -> String (String builds Constant node)
        # Literal -> QuotedWordList (pass through)
        # Literal -> RegexPattern (RegexPattern builds Constant node)
        # Literal -> RegexSubstitution (RegexSubstitution builds Constant node)
        # Literal -> EmptyList (pass through)
        # Literal -> 'undef' (handled below)
        # Literal -> 'true' (handled below)
        # Literal -> 'false' (handled below)

        my $child = $context->child(0);

        # If child is already an IR node (from Number, String, etc.), pass through
        if (ref($child) && $child->can('id')) {
            return $child;
        }

        # Handle keyword literals: 'undef', 'true', 'false'
        my $token_str = defined($child) ? "$child" : '';

        if ($token_str eq 'undef') {
            return Chalk::IR::Node::Constant->new(
                type  => Chalk::Grammar::Chalk::Type::Undef->new(),
                value => undef,
            );
        }

        if ($token_str eq 'true') {
            return Chalk::IR::Node::Constant->new(
                type  => Chalk::Grammar::Chalk::Type::Boolean->new(),
                value => 1,
            );
        }

        if ($token_str eq 'false') {
            return Chalk::IR::Node::Constant->new(
                type  => Chalk::Grammar::Chalk::Type::Boolean->new(),
                value => 0,
            );
        }

        # For other cases (like EmptyList), pass through
        return $child;
    }
}

1;
