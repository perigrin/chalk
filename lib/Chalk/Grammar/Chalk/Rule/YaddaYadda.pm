# ABOUTME: Semantic action for YaddaYadda - the ... (yada-yada) operator
# ABOUTME: Generates Die IR node with "Unimplemented" message when evaluated

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::YaddaYadda :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Die;
        use Chalk::IR::Node::Constant;
        use Chalk::Grammar::Chalk::Type::Str;

        # YaddaYadda -> '...'

        # The yada-yada operator is a placeholder that dies when executed
        # In Perl, it throws: "Unimplemented at <file> line <line>"

        # Create "Unimplemented" constant message
        my $message = Chalk::IR::Node::Constant->new(
            value => 'Unimplemented',
            type  => Chalk::Grammar::Chalk::Type::Str->new(),
        );

        # Get scope for control flow
        my $scope = $context->env->{scope};
        my $current_control = $scope ? $scope->current_control : undef;

        # Create Die node with control and message
        my $die_node = Chalk::IR::Node::Die->new(
            control => $current_control,
            message => $message,
        );

        # Kill control after die - similar to return
        if ($scope && $scope->can('with_binding')) {
            my $dead_scope = $scope->with_binding('$ctrl', undef);
            $context->env->{scope} = $dead_scope;
        }

        return $die_node;
    }
}

1;
