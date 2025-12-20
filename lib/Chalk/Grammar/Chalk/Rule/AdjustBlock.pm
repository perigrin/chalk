# ABOUTME: Semantic action for AdjustBlock - ADJUST { } in class definitions
# ABOUTME: Returns block statements for Constructor to execute after field init
use 5.42.0;
use experimental 'class';
use Chalk::Grammar;  # Provides Chalk::GrammarRule base class

class Chalk::Grammar::Chalk::Rule::AdjustBlock :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # AdjustBlock -> 'ADJUST' WS_OPT Block
        # Child 0: 'ADJUST' literal
        # Child 1: WS_OPT (whitespace)
        # Child 2: Block

        my @children = $context->children->@*;

        # Get the Block child (last child)
        my $block_result = $context->child($#children);

        # If Block returns a hashref with statements, wrap it as an ADJUST block
        if (ref($block_result) eq 'HASH' && $block_result->{type} eq 'block') {
            return {
                type => 'adjust',
                statements => $block_result->{statements},
            };
        }

        # If Block returns something else (e.g., a single node), wrap it
        if (blessed($block_result) && $block_result->can('id')) {
            return {
                type => 'adjust',
                statements => [ $block_result ],
            };
        }

        # Return as-is with adjust type marker
        return {
            type => 'adjust',
            statements => [],
        };
    }
}

1;
