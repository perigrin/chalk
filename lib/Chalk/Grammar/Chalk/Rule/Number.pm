# ABOUTME: Semantic action for Number - builds Constant IR node with Type object
# ABOUTME: Converts numeric literals to Constant nodes with appropriate Type

use 5.42.0;
use experimental 'class';
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Num;

class Chalk::Grammar::Chalk::Rule::Number :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # Number -> %INTEGER% | %FLOAT%
        # Child [0] contains the matched number token

        my $token = $context->child(0);
        die "Number::evaluate matched but child(0) is undefined - grammar bug" unless defined $token;

        # Convert to numeric value
        my $value = "$token" + 0;

        # Create Constant node with appropriate Type object
        if ($token isa Chalk::Grammar::Token::Float) {
            # Float literal -> Constant with TypeFloat
            return Chalk::IR::Node::Constant->new(
                type  => Chalk::IR::Type::Float->constant($value),
                value => $value,
            )->peephole();
        } elsif ($token isa Chalk::Grammar::Token::Int) {
            # Integer literal -> Constant with TypeInteger
            return Chalk::IR::Node::Constant->new(
                type  => Chalk::IR::Type::Integer->constant($value),
                value => $value,
            )->peephole();
        } else {
            # All tokens should be blessed - if not, something is wrong in the Parser
            my $desc = ref($token) || (defined $token ? "'$token'" : 'undef');
            die "Number::evaluate expected Token::Int or Token::Float, got: $desc";
        }
    }

    # Grammar type inference for field type narrowing
    # Returns Int for integer literals, Num for float literals
    method grammar_type($context) {
        my $token = $context->child(0);
        return Chalk::Grammar::Chalk::Type::Num->new()
            if $token isa Chalk::Grammar::Token::Float;
        return Chalk::Grammar::Chalk::Type::Int->new();
    }
}

1;
