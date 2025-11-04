# ABOUTME: Semantic action for BuiltinOp - delegates to FunctionCall with optimization opportunity
# ABOUTME: Pass-through wrapper that can specialize known builtins (exists, defined, length, etc.)

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::BuiltinOp :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # BuiltinOp -> FunctionCall

        # Get the FunctionCall result
        my $func_call = $context->child(0);

        # TODO: In the future, we can check if this is a known builtin
        # and generate specialized IR nodes:
        #   - exists() -> ExistsNode
        #   - defined() -> DefinedNode
        #   - length() -> LengthNode
        #   - blessed() -> BlessedNode
        #   - etc.
        #
        # For now, just pass through the FunctionCall
        return $func_call;
    }
}

1;
