# ABOUTME: Semantic action for Integer literal (v2 rewrite)
# ABOUTME: Creates Constant node from matched digits
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Integer2 {
    use Chalk::IR::Node::Constant2;

    method evaluate($context) {
        my $digits = $context->child(0);
        # Handle both string and token objects
        $digits = "$digits" if ref($digits);

        return Chalk::IR::Node::Constant2->new(
            type  => 'Int',
            value => $digits + 0,  # Ensure numeric
        );
    }
}

1;
