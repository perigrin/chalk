# ABOUTME: Semantic action for Attribute rule in Chalk grammar
# ABOUTME: Passes through attribute tokens for class field declarations
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::Attribute :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Attribute -> ':param'
        # Attribute -> ':reader'
        # Attribute -> ':reader' '(' Identifier ')'
        # Attribute -> ':isa' '(' QualifiedIdentifier ')'
        # Pass through first child (the attribute token)
        return $context->child(0);
    }
}

1;
