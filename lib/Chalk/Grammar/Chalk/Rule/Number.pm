# ABOUTME: Semantic action for Number - builds Constant IR node
# ABOUTME: Converts numeric literals to Constant nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Number :isa(Chalk::GrammarRule) {
    use Chalk::IR::Node::Constant;

    method evaluate($context) {
        # Number -> %INTEGER% | %FLOAT%
        # Child [0] contains the matched number token

        my $token = $context->child(0);
        return unless defined $token;

        # Determine type from token class
        my $type;
        if ($token isa Chalk::Grammar::Token::Float) {
            $type = 'Float';
        } elsif ($token isa Chalk::Grammar::Token::Int) {
            $type = 'Int';
        } else {
            # All tokens should be blessed - if not, something is wrong in the Parser
            my $desc = ref($token) || (defined $token ? "'$token'" : 'undef');
            die "Number::evaluate expected Token::Int or Token::Float, got: $desc";
        }

        # Convert to numeric value
        my $value = "$token" + 0;

        # Create Constant node directly (content-addressable ID)
        return Chalk::IR::Node::Constant->new(
            type  => $type,
            value => $value,
        );
    }
}

1;
