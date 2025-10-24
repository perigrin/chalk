# ABOUTME: Semantic action for VariableDeclaration - creates Store IR nodes for variable assignments
# ABOUTME: VariableDeclaration handles my/our/state variable declarations with initialization

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::VariableDeclaration :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable WS_OPT AttributeList
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable WS_OPT '=' WS_OPT Expression
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable WS_OPT AttributeList WS_OPT '=' WS_OPT Expression
        # VariableDeclaration -> LexicalDeclarator WS_OPT '(' WS_OPT VariableList WS_OPT ')' WS_OPT '=' WS_OPT Expression

        my $builder = $context->env->{ir_builder};
        my @children = $context->children->@*;

        # Find the '=' to determine if this is an initialized declaration
        my $has_init = 0;
        my $equals_index = -1;
        for my $i (0..$#children) {
            my $child = $children[$i]->extract;
            if (defined $child && !ref($child) && $child eq '=') {
                $has_init = 1;
                $equals_index = $i;
                last;
            }
        }

        unless ($has_init && $builder) {
            # No initialization or no builder - just return undef for now
            # TODO: Handle uninitialized declarations
            return undef;
        }

        # Get the variable (child 2)
        my $var = $context->child(2);

        # Extract variable name from metadata hashref
        my $var_name;
        if (ref($var) eq 'HASH' && $var->{type} eq 'scalar_var') {
            $var_name = $var->{name};
        } else {
            # Unsupported variable type
            return undef;
        }

        # Get the expression value (child after '=' + WS_OPT, which is equals_index + 2)
        my $expr_index = $equals_index + 2;
        my $value = $context->child($expr_index);

        # Validate we got an IR node
        return undef unless (blessed($value) && $value->can('id'));

        # Create Store node with placeholder control
        # Parent rule (Block, ConditionalStatement, WhileStatement) will wire actual control
        return $builder->build_store_node($var_name, $value, '__CONTROL_PLACEHOLDER__');
    }
}

1;
