# ABOUTME: Semantic action for VariableDeclaration - declares variables in scope
# ABOUTME: Creates binding for my/our/state declarations; Assignment handles initialization

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::VariableDeclaration :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable WS_OPT AttributeList
        #
        # Declaration creates the binding in scope. Assignment handles initialization.
        # Variable returns UnboundVariable which provides name() for binding.

        my $scope = $context->env->{scope};
        return undef unless $scope;

        # Get the variable (child 2) - should be UnboundVariable with name()
        my $var = $context->child(2);

        # Duck-type: any node with name() can be declared
        return undef unless $var && $var->can('name');

        my $var_name = $var->name;

        # Create binding in scope to the UnboundVariable itself
        # Assignment will update this binding with the actual value
        my $new_scope = $scope->with_binding($var_name, $var);

        # Update env's scope reference
        $context->env->{scope} = $new_scope;

        # Return the UnboundVariable - Assignment will use this
        return $var;
    }
}

1;
