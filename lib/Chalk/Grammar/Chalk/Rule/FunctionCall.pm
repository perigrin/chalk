# ABOUTME: Semantic action for FunctionCall - function and method calls
# ABOUTME: Generates Call/CallEnd IR nodes for function invocation

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::FunctionCall :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Call;
        use Chalk::IR::Node::CallEnd;
        use Chalk::IR::Node::Constant;
        use Chalk::Grammar::Chalk::Type::Str;

        # FunctionCall -> Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # FunctionCall -> Identifier '(' WS_OPT ')'
        # FunctionCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # FunctionCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ')'

        my @children = $context->children->@*;

        # Get function name/callee - first child is Identifier
        my $callee = $context->child(0);

        # If callee is not an IR node, wrap it as Constant
        unless (blessed($callee) && $callee->can('id')) {
            my $name = defined($callee) ? "$callee" : 'unknown';
            $callee = Chalk::IR::Node::Constant->new(
                value => $name,
                type => Chalk::Grammar::Chalk::Type::Str->new(),
            );
        }

        # Collect arguments - scan evaluated children for IR nodes (skip callee)
        my @args;
        my $num_children = scalar(@children);
        for my $i (0 .. $num_children - 1) {
            # Skip callee (index 0)
            next if $i == 0;

            my $child = $context->child($i);

            # Skip non-IR nodes (tokens like '(', ')', ',')
            next unless blessed($child) && $child->can('id');
            push @args, $child;
        }

        # Create Call node
        my $call = Chalk::IR::Node::Call->new(
            callee => $callee,
            args => \@args,
        );

        # Create CallEnd node (return this as the expression value)
        my $call_end = Chalk::IR::Node::CallEnd->new(
            call => $call,
        );

        return $call_end;
    }
}

1;
