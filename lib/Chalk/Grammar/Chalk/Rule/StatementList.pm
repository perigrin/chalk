# ABOUTME: Semantic action for StatementList - collects statements into array for Program
# ABOUTME: Handles recursive statement collection from parse tree

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;

class Chalk::Grammar::Chalk::Rule::StatementList :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # StatementList has multiple alternatives:
        # StatementList -> Statement WS_OPT ';' WS_OPT StatementList (recursive with semicolon)
        # StatementList -> Statement WS_OPT StatementList (recursive without semicolon)
        # StatementList -> Statement WS_OPT (base case - single statement)
        # StatementList -> (empty)

        my @children = $context->children->@*;

        # Empty StatementList
        return [] if @children == 0;

        # Handle edge case: single child that's already an evaluated StatementList array
        # This occurs when Statement passes through an already-evaluated StatementList
        # from a child grammar rule (observed in early-return control flow scenarios)
        if (@children == 1) {
            my $child_focus = $context->child(0);
            if (ref($child_focus) eq 'ARRAY') {
                return $child_focus;  # Already evaluated, pass it through
            }
            # Single IR node child - return as single-element array
            if (blessed($child_focus) && $child_focus->can('id')) {
                return [$child_focus];
            }
            return [];
        }

        # Get the first statement
        my $stmt = $context->child(0);

        # Base case: single statement (StatementList -> Statement WS_OPT)
        if (@children == 2) {
            return blessed($stmt) && $stmt->can('id') ? [$stmt] : [];
        }

        # Recursive cases: collect statements
        my @statements;
        if (blessed($stmt) && $stmt->can('id')) {
            push @statements, $stmt;
        }

        # Find the recursive StatementList (last child after WS_OPT and optional ';')
        my $rest_list = $context->child(-1);  # Last child is the recursive StatementList

        # If rest_list has statements, add them
        if (ref($rest_list) eq 'ARRAY') {
            push @statements, $rest_list->@*;
        } elsif (blessed($rest_list) && $rest_list->can('id')) {
            push @statements, $rest_list;
        }

        return \@statements;
    }
}

1;
