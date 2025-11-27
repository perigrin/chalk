# ABOUTME: Semantic action for VariableDeclaration - binds variables to IR nodes using SSA
# ABOUTME: VariableDeclaration handles my/our/state variable declarations with initialization

use 5.42.0;
use experimental 'class';
use Scalar::Util qw(blessed);

class Chalk::Grammar::Chalk::Rule::VariableDeclaration :isa(Chalk::GrammarRule) {
    use Chalk::IR::Node::Store;

    method evaluate($context) {
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable WS_OPT '=' WS_OPT Expression

        my @children = $context->children->@*;
        my $scope = $context->env->{scope};
        return undef unless $scope;

        # Find the '=' to determine if this is an initialized declaration
        my $has_init = 0;
        my $equals_index = -1;
        for my $i (0..$#children) {
            my $child = $children[$i];
            my $extracted = blessed($child) && $child->can('extract') ? $child->extract : $child;
            if (defined($extracted) && "$extracted" eq '=') {
                $has_init = 1;
                $equals_index = $i;
                last;
            }
        }

        unless ($has_init) {
            # No initialization - return undef for now
            return undef;
        }

        # Get the variable (child 2)
        my $var = $context->child(2);

        # Extract variable name from metadata hashref
        my $var_name;
        if (ref($var) eq 'HASH' && $var->{type} && $var->{type} eq 'scalar_var') {
            $var_name = $var->{name};
        } else {
            return undef;
        }

        # Get the expression value (child after '=' + WS_OPT)
        my $expr_index = $equals_index + 2;
        my $value = $context->child($expr_index);

        # Validate we got an IR node
        unless (blessed($value) && $value->can('id')) {
            return undef;
        }

        # Get current control from scope
        my $current_control = $scope->current_control;
        return undef unless $current_control;

        # Create Store node directly (content-addressable ID)
        my $store = Chalk::IR::Node::Store->new(
            control => $current_control,
            var     => $var_name,
            value   => $value,
        );

        # Update scope immutably: create new scope with binding and control
        my $new_scope = $scope->with_binding($var_name, $value);
        $new_scope = $new_scope->with_control($store);

        # Update env's scope reference to the new immutable scope
        $context->env->{scope} = $new_scope;

        # Return the Store node
        return $store;
    }
}

1;
