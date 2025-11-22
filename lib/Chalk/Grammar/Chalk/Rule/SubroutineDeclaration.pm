# ABOUTME: Semantic action for SubroutineDeclaration rule in Chalk grammar
# ABOUTME: Returns placeholder for subroutine declaration (IR building TODO)
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::SubroutineDeclaration :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # TODO: Build proper subroutine definition IR node
        # For now, return the Block child (last child)
        my @children = $context->children->@*;
        return $context->child($#children);
    }
}

1;
