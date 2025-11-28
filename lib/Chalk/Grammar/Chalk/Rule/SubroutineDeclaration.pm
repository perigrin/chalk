# ABOUTME: Semantic action for SubroutineDeclaration rule in Chalk grammar
# ABOUTME: Returns placeholder for subroutine declaration (see issue #133)
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::SubroutineDeclaration :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # See issue #133 for proper FunctionDef IR node implementation
        # For now, return the Block child (last child)
        my @children = $context->children->@*;
        return $context->child($#children);
    }
}

1;
