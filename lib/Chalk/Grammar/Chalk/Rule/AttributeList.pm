# ABOUTME: Semantic action for AttributeList rule in Chalk grammar
# ABOUTME: Passes through Attribute or recursive Attribute WS_OPT AttributeList
use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::AttributeList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # AttributeList -> Attribute (pass through)
        # AttributeList -> Attribute WS_OPT AttributeList (pass through first Attribute)
        return $context->child(0);
    }
}

1;
