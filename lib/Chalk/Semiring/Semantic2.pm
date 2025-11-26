# ABOUTME: Simplified Semantic semiring (v2 rewrite)
# ABOUTME: Provides scope to Rules, dispatches evaluation
use 5.42.0;
use experimental qw(class);

class Chalk::Semiring::Semantic2 {
    use Chalk::IR::Node::Scope2;

    field $env :param :reader = {};

    ADJUST {
        $env->{scope} //= Chalk::IR::Node::Scope2->new();
    }

    method one() {
        return 1;  # Identity
    }

    method zero() {
        return 0;  # Failure
    }

    method evaluate($rule_name, $context) {
        # Inject env into context
        $context->set_env($env) if $context->can('set_env');

        # Look up Rule class
        my $rule_class = "Chalk::Grammar::Chalk::Rule::${rule_name}";
        if ($rule_class->can('evaluate')) {
            my $rule = $rule_class->new();
            return $rule->evaluate($context);
        }

        # Pass through first child if no semantic action
        return $context->child(0) if $context->can('child');
        return undef;
    }
}

1;
