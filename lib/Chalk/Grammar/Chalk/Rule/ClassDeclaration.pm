# ABOUTME: Semantic action for ClassDeclaration rule in Chalk grammar
# ABOUTME: Returns placeholder for class declaration (IR building TODO)
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ClassDeclaration :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # TODO: Build proper ClassDef IR node
        # For now, return the Block child (last child)
        my @children = $context->children->@*;
        return $context->child($#children);
    }
}

1;
