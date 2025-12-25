# ABOUTME: Semantic action for DeclaredVariable - variable that must exist in scope
# ABOUTME: Wraps Variable, does scope lookup, returns IR node or UnboundVariable
use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::UnboundVariable;

class Chalk::Grammar::Chalk::Rule::DeclaredVariable :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # DeclaredVariable -> Variable
        # Variable returns metadata hash, we do scope lookup

        my $var_metadata = $context->child(0);

        # If Variable already returned an IR node (found in scope), pass through
        if (blessed($var_metadata) && $var_metadata->can('id')) {
            return $var_metadata;
        }

        # Expect metadata hash from Variable
        unless (ref($var_metadata) eq 'HASH' && $var_metadata->{type}) {
            # Not metadata, not IR node - something unexpected
            return undef;
        }

        # Extract variable name
        my $sigil = $var_metadata->{sigil} // '';
        my $name = $var_metadata->{name} // '';
        my $full_name = $sigil . $name;

        # Look up in scope
        my $scope = $context->env->{scope};
        if ($scope) {
            my $node = $scope->lookup($full_name);
            if (defined($node) && blessed($node) && $node->can('id')) {
                return $node;
            }
        }

        # Variable not found in scope - return UnboundVariable
        # This preserves the name for later resolution (e.g., function parameters)
        # or for strict mode error reporting
        return Chalk::IR::Node::UnboundVariable->new(name => $full_name);
    }
}

1;
