# ABOUTME: Semantic action for PostfixConditionalStatement - handles postfix if/unless modifiers
# ABOUTME: Reconstructs statement node with correct control for conditional execution

use 5.42.0;
use experimental 'class';
use Scalar::Util qw(blessed);

class Chalk::Grammar::Chalk::Rule::PostfixConditionalStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::If;
        use Chalk::IR::Node::Proj;
        use Chalk::IR::Node::Region;

        # PostfixConditionalStatement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
        # child[0] = Statement (inner statement's IR node)
        # child[2] = ConditionalKeyword ('if' or 'unless')
        # child[4] = Expression (condition)

        my $stmt_node = $context->child(0);
        my $keyword_node = $context->children->[2];
        my $condition = $context->child(4);

        # If inner statement isn't an IR node, pass through
        return $stmt_node unless blessed($stmt_node) && $stmt_node->can('id');

        # Extract keyword
        my $keyword = blessed($keyword_node) && $keyword_node->can('extract')
            ? $keyword_node->extract
            : "$keyword_node";
        return $stmt_node unless $keyword eq 'if' || $keyword eq 'unless';

        # Condition must be an IR node
        return $stmt_node unless blessed($condition) && $condition->can('id');

        # Get scope for control flow
        my $scope = $context->env->{scope};
        return $stmt_node unless (ref($scope) && $scope->can('current_control'));

        my $current_control = $scope->current_control;
        return $stmt_node unless $current_control;

        # Build If node for condition
        my $if_node = Chalk::IR::Node::If->new(
            control   => $current_control,
            condition => $condition,
        );

        # Build projections
        my $if_true = Chalk::IR::Node::Proj->new(
            control => $if_node,
            which   => 0,  # true branch
        );
        my $if_false = Chalk::IR::Node::Proj->new(
            control => $if_node,
            which   => 1,  # false branch
        );

        # Determine which branch executes the statement
        my ($stmt_control, $passthrough_control) = $keyword eq 'if'
            ? ($if_true, $if_false)
            : ($if_false, $if_true);

        # Reconstruct statement with correct control (immutable)
        my $rewired_stmt;
        if ($stmt_node->can('with_control')) {
            $rewired_stmt = $stmt_node->with_control($stmt_control);
        } else {
            # Fallback: return as-is if node doesn't support reconstruction
            $rewired_stmt = $stmt_node;
        }

        # Build Region to merge paths
        my $region = Chalk::IR::Node::Region->new(
            inputs => [$rewired_stmt, $passthrough_control],
        );

        # Update scope immutably with new control at merge point
        my $new_scope = $scope->with_control($region);
        $context->env->{scope} = $new_scope;

        return $region;
    }
}

1;
