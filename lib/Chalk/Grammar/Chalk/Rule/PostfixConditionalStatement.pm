# ABOUTME: Semantic action for PostfixConditionalStatement - handles postfix if/unless modifiers
# ABOUTME: Reconstructs statement node with correct control for conditional execution

use 5.42.0;
use experimental 'class';


class Chalk::Grammar::Chalk::Rule::PostfixConditionalStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::If;
        use Chalk::IR::Node::Proj;
        use Chalk::IR::Node::Region;

        # PostfixConditionalStatement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
        # WS_OPT is NOT collapsed - must scan for IR nodes and keywords

        my @children = $context->children->@*;

        # Find first IR node (the Statement)
        my $stmt_node;
        for my $i (0 .. $#children) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                $stmt_node = $child;
                last;
            }
        }

        unless (defined($stmt_node)) {
            # No IR node found for statement - this parse path is invalid
            # Return undef to let parser backtrack and try other alternatives
            return undef;
        }

        # Find keyword ('if' or 'unless') by scanning for string match
        my $keyword;
        for my $i (0 .. $#children) {
            my $child_ctx = $children[$i];
            my $extracted = $child_ctx->extract;
            next unless defined $extracted;
            my $str_val = "$extracted";
            if ($str_val eq 'if' || $str_val eq 'unless') {
                $keyword = $str_val;
                last;
            }
        }
        unless (defined($keyword)) {
            # No keyword found - this parse path is invalid
            return undef;
        }

        # Find last IR node (the condition Expression)
        my $condition;
        for my $i (reverse 0 .. $#children) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                # Skip if this is the same as stmt_node (need different node)
                next if refaddr($child) == refaddr($stmt_node);
                $condition = $child;
                last;
            }
        }

        unless (defined($condition)) {
            # No IR node found for condition - this parse path is invalid
            return undef;
        }

        # Get scope for control flow
        my $scope = $context->env->{scope};
        die "PostfixConditionalStatement: scope required in evaluation context" unless $scope;

        my $current_control = $scope->current_control;
        die "PostfixConditionalStatement: current_control required in scope" unless $current_control;

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
