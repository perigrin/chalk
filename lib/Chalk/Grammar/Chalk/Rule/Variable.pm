# ABOUTME: Semantic action for Variable - pass through variable metadata or complex variable operations
# ABOUTME: Variable delegates to ScalarVar, ArrayVar, HashVar, or handles complex variable operations

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Variable :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Variable -> ScalarVar (pass-through)
        # Variable -> ArrayVar (TODO)
        # Variable -> HashVar (TODO)
        # Variable -> ArraySize (TODO)
        # Variable -> Variable '->' ... (TODO: complex variable operations)

        # For now, just pass through the first child
        # ScalarVar returns a metadata hashref that Primary will use to create Load nodes
        return $context->child(0);
    }
}

1;
