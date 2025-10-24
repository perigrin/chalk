# ABOUTME: Semantic action for BreakStatement - returns metadata for parent to handle
# ABOUTME: Uses placeholder control pattern - parent (WhileStatement) wires control flow

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::BreakStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # BreakStatement -> 'break' WS_OPT
        # Break doesn't create its own IR node during parsing
        # Instead, it returns metadata marking this as a break statement
        # The parent rule (WhileStatement) will:
        #   1. Track this control path
        #   2. Wire it to the loop exit Region
        #   3. NOT add a backedge for this path

        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        # Return metadata for parent to handle
        # This uses a similar pattern to Return and Assignment
        return {
            type => 'break',
            control => '__CONTROL_PLACEHOLDER__',
        };
    }
}

1;
