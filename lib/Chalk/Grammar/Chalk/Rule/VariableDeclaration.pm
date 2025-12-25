# ABOUTME: Semantic action for VariableDeclaration - binds variables to IR nodes using SSA
# ABOUTME: VariableDeclaration handles my/our/state variable declarations with initialization

use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Store;

class Chalk::Grammar::Chalk::Rule::VariableDeclaration :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable
        # VariableDeclaration -> LexicalDeclarator WS_OPT Variable WS_OPT '=' WS_OPT Expression

        my @children = $context->children->@*;
        my $scope = $context->env->{scope};
        die "VariableDeclaration: scope required in evaluation context" unless $scope;

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
        my $var_type;
        if (ref($var) eq 'HASH' && $var->{type}) {
            $var_type = $var->{type};
            my $name = $var->{name};
            my $sigil = $var->{sigil};

            if ($var_type eq 'scalar_var') {
                # Scalars are stored with $ sigil to match Variable/DeclaredVariable lookup
                $var_name = '$' . $name;
            } elsif ($var_type eq 'array_var') {
                # Arrays are stored with @ sigil
                $var_name = '@' . $name;
            } elsif ($var_type eq 'hash_var') {
                # Hashes are stored with % sigil
                $var_name = '%' . $name;
            } else {
                die "VariableDeclaration: unknown variable type: $var_type";
            }
        } else {
            my $desc = ref($var) || (defined $var ? "'$var'" : 'undef');
            die "VariableDeclaration: expected variable hashref, got: $desc";
        }

        # Get the expression value (child after '=' + WS_OPT)
        my $expr_index = $equals_index + 2;
        my $value = $context->child($expr_index);

        # Validate we got an IR node
        unless (blessed($value) && $value->can('id')) {
            my $desc = ref($value) || (defined $value ? "'$value'" : 'undef');
            die "VariableDeclaration: expression must be an IR node with id(), got: $desc";
        }

        # Get current control from scope
        my $current_control = $scope->current_control;
        die "VariableDeclaration: current_control required in scope" unless $current_control;

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
