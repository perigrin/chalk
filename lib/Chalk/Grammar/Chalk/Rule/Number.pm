# ABOUTME: Semantic action for Number - builds Constant IR node
# ABOUTME: Converts numeric literals to Constant nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Number :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Number -> %INTEGER%  (or %FLOAT% or %VERSION%)
        # Child [0] contains the matched number string

        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        my $number_str = $context->child(0);

        # Determine type (Int vs Float)
        my $type = (index($number_str, '.') != -1) ? 'Float' : 'Int';
        my $value = $number_str + 0;  # Convert to numeric

        # Build and return Constant IR node
        return $builder->build_constant_node($value, $type);
    }
}

1;
