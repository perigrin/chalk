# ABOUTME: Semantic action for Statement - handles postfix statement modifiers (if/unless/while/until/for)
# ABOUTME: Desugars `stmt if cond` into equivalent IR structure of `if (cond) { stmt }`

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

class Chalk::Grammar::Chalk::Rule::Statement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # Statement has multiple alternatives, but we only handle the postfix modifier form here:
        # Statement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
        #
        # For example: print($x) if $y
        # Indices:     0         1     2                3     4
        # child[0] = Statement node (print($x))
        # child[2] = ConditionalKeyword ('if' or 'unless')
        # child[4] = Expression node ($y)

        my @children = $context->children->@*;
        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        # Check if this is the postfix modifier form (has 5 children)
        return undef unless @children == 5;

        # Get the statement (child 0)
        my $stmt = $context->child(0);
        return undef unless (blessed($stmt) && $stmt->can('id'));

        # Get the conditional keyword (child 2)
        my $keyword_node = $children[2];
        my $keyword = $keyword_node->extract;
        return undef unless defined($keyword) && ($keyword eq 'if' || $keyword eq 'unless');

        # Get the condition expression (child 4)
        my $condition = $context->child(4);
        return undef unless (blessed($condition) && $condition->can('id'));

        # Save current control before building If structure
        my $entry_control = $builder->current_control;
        die "Internal error: current_control is undefined during statement modifier evaluation"
            unless defined($entry_control);

        # Build If node for the condition
        my $if_node = $builder->build_if_node($condition);
        my $if_true = $builder->build_if_true_node($if_node);
        my $if_false = $builder->build_if_false_node($if_node);

        # For 'if': statement executes on true path
        # For 'unless': statement executes on false path (inverted logic)
        my ($stmt_control, $passthrough_control);
        if ($keyword eq 'if') {
            $stmt_control = $if_true->id;
            $passthrough_control = $if_false->id;
        } else {  # 'unless'
            $stmt_control = $if_false->id;
            $passthrough_control = $if_true->id;
        }

        # Wire the statement to the appropriate control branch
        # Bottom-up parsing means the statement was evaluated before this semantic action,
        # so its control is already wired. We need to rewire it to our branch control.
        my $stmt_input = $stmt->inputs->[0];
        die "Internal error: Statement node has no control input (expected either placeholder or control ID)"
            unless defined($stmt_input);

        # Rewire statement to execute on the appropriate branch (always use the builder method)
        $builder->set_node_control($stmt, $stmt_control);

        # After statement executes, its output becomes the merge input
        my $stmt_exit_control = $stmt->id;

        # Build Region to merge the two paths:
        # - Path with statement execution (stmt_exit_control)
        # - Passthrough path (condition not met)
        my $region = $builder->build_region_node($stmt_exit_control, $passthrough_control);
        $builder->set_control($region->id);

        # Return the Region node (represents the merge point)
        return $region;
    }
}

1;
