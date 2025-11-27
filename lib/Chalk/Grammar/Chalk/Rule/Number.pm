# ABOUTME: Semantic action for Number - builds Constant IR node
# ABOUTME: Converts numeric literals to Constant nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Number :isa(Chalk::GrammarRule) {
    use Chalk::IR::Node::Constant;

    method evaluate($context) {
        # Number -> %INTEGER% | %FLOAT%
        # Child [0] contains the matched number string

        my $number_str = $context->child(0);
        return undef unless defined $number_str;

        # Handle both string and token objects
        $number_str = "$number_str" if ref($number_str);

        # Determine type (Int vs Float)
        my $type  = $number_str =~ qr/\./ ? 'Float' : 'Int';
        my $value = $number_str + 0;  # Convert to numeric

        # Create Constant node directly (content-addressable ID)
        return Chalk::IR::Node::Constant->new(
            type  => $type,
            value => $value,
        );
    }
}

1;
