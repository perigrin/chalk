# ABOUTME: Semantic action for Number - builds Constant IR node
# ABOUTME: Converts numeric literals to Constant nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Number :isa(Chalk::GrammarRule) {

    use Carp qw(confess);

    method evaluate($context) {

        # Number -> %INTEGER% | %FLOAT%
        # Child [0] contains the matched number string

        my $builder = $context->env->{ir_builder};
        return unless $builder;

        my $number_str = $context->child(0);
        confess "Invalid number in context: $context"
          unless defined $number_str;

        # Determine type (Int vs Float)
        my $type  = $number_str =~ qr/\./ ? 'Float' : 'Int';
        my $value = $number_str + 0;                        # Convert to numeric

        # Build and return Constant IR node
        return $builder->build_constant_node( $value, $type );
    }
}

1;
