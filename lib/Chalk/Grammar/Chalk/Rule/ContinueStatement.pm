# ABOUTME: Semantic action for ContinueStatement - returns metadata for parent to handle
# ABOUTME: Uses placeholder control pattern - parent (WhileStatement) wires control flow

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ContinueStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ContinueStatement -> 'continue' WS_OPT
        # Continue doesn't create its own IR node during parsing
        # Instead, it returns metadata marking this as a continue statement
        # The parent rule (WhileStatement) will:
        #   1. Track this control path
        #   2. Add it to the loop backedge (merge point)
        #   3. Skip remaining body statements for this path

        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        # Return metadata for parent to handle
        # This uses a similar pattern to Return and Assignment
        return {
            type => 'continue',
            control => '__CONTROL_PLACEHOLDER__',
        };
    }
}

1;
