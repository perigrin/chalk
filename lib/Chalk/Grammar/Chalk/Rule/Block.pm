# ABOUTME: Semantic action for Block - collects statements and returns them to parent
# ABOUTME: Parent rule (ConditionalStatement, Loop, etc) is responsible for wiring control

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

class Chalk::Grammar::Chalk::Rule::Block :isa(Chalk::GrammarRule) {
    # Helper to recursively flatten arrays and extract nodes
    sub _flatten_to_nodes {
        my ($value) = @_;
        my @results;

        if (blessed($value) && $value->can('id')) {
            # This is an IR node - return it
            return ($value);
        } elsif (ref($value) eq 'ARRAY') {
            # Recursively flatten array
            for my $elem ($value->@*) {
                push @results, _flatten_to_nodes($elem);
            }
        }
        # Scalars, undefs, etc. are ignored

        return @results;
    }

    method evaluate($context) {
        # Block has multiple alternatives in the grammar:
        # Block -> ClassDeclaration | MethodDeclaration | AdjustBlock |
        #          LexicalSubroutine | SubroutineDeclaration |
        #          ConditionalStatement | WhileStatement | ForStatement |
        #          '{' WS_OPT StatementList WS_OPT '}'
        #
        # For most alternatives, we just pass through the child result
        # For the '{' ... '}' case, we build the block metadata

        my @children = $context->children->@*;

        # If first child is '{', this is a statement block
        my $first_child = $context->child(0);
        if (defined($first_child) && $first_child eq '{') {
            # Block -> '{' WS_OPT StatementList WS_OPT '}'
            my $builder = $context->env->{ir_builder};
            return undef unless $builder;

            # Get StatementList (child 2)
            my $statements = $context->child(2);
            return undef unless $statements;

            # Statements might be a single node or nested arrays containing nodes
            # Use helper to recursively flatten and extract all IR nodes
            my @stmt_nodes = _flatten_to_nodes($statements);
            return undef unless @stmt_nodes;

            # Return metadata about this block for parent to wire up
            # Parent needs: the statements with placeholders, entry/exit info
            return {
                type => 'block',
                statements => \@stmt_nodes,
                entry => '__BLOCK_ENTRY__',  # Parent will provide
                exit => '__BLOCK_EXIT__',    # Will be last statement's control out
            };
        }

        # Not a '{ }' block - this is one of the other Block alternatives
        # (ConditionalStatement, ClassDeclaration, etc.)
        # Just pass through the child result
        return $context->child(0);
    }
}

1;
