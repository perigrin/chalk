# ABOUTME: Semantic action for MethodCall - instance and class method invocations
# ABOUTME: Generates Call/CallEnd IR nodes with receiver for $obj->method() calls

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::MethodCall :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Call;
        use Chalk::IR::Node::CallEnd;
        use Chalk::IR::Node::Constant;
        use Chalk::Grammar::Chalk::Type::Str;

        # MethodCall -> Variable '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # MethodCall -> Variable '->' Identifier  # Without parens
        # MethodCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # MethodCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ')'

        my @children = $context->children->@*;
        my $num_children = scalar(@children);

        # Get receiver (first child - object or class)
        my $receiver = $context->child(0);

        # If receiver is not an IR node, wrap it as Constant
        unless (blessed($receiver) && $receiver->can('id')) {
            my $name = defined($receiver) ? "$receiver" : 'unknown';
            $receiver = Chalk::IR::Node::Constant->new(
                value => $name,
                type => Chalk::Grammar::Chalk::Type::Str->new(),
            );
        }

        # Find method name (after '->')
        # Pattern: receiver '->' method_name [( args )]
        my $callee;
        my $found_arrow = 0;
        for my $i (0 .. $num_children - 1) {
            my $child = $context->child($i);

            # Skip until we find '->'
            if (!$found_arrow) {
                my $focus = $children[$i]->focus if $children[$i]->can('focus');
                if (defined($focus) && "$focus" eq '->') {
                    $found_arrow = 1;
                }
                next;
            }

            # First IR node after '->' is the method name
            if (blessed($child) && $child->can('id')) {
                $callee = $child;
                last;
            }
        }

        # If callee is still not found, try to extract from children directly
        if (!defined($callee)) {
            # Method name is typically child(2) in: receiver '->' method_name
            my $candidate = $context->child(2);
            if (blessed($candidate) && $candidate->can('id')) {
                $callee = $candidate;
            } else {
                # Wrap as constant if needed
                my $name = defined($candidate) ? "$candidate" : 'method';
                $callee = Chalk::IR::Node::Constant->new(
                    value => $name,
                    type => Chalk::Grammar::Chalk::Type::Str->new(),
                );
            }
        }

        # Collect arguments - scan for IR nodes after '('
        my @args;
        my $seen_open_paren = 0;
        for my $i (0 .. $num_children - 1) {
            my $focus = $children[$i]->focus if $children[$i] && $children[$i]->can('focus');

            if (!$seen_open_paren && defined($focus) && "$focus" eq '(') {
                $seen_open_paren = 1;
                next;
            }

            if ($seen_open_paren) {
                my $child = $context->child($i);
                next unless blessed($child) && $child->can('id');
                # Skip callee and receiver which we already have
                next if defined($callee) && $child->id eq $callee->id;
                next if defined($receiver) && $child->id eq $receiver->id;
                push @args, $child;
            }
        }

        # Create Call node with receiver
        my $call = Chalk::IR::Node::Call->new(
            callee   => $callee,
            args     => \@args,
            receiver => $receiver,
        );

        # Create CallEnd node (return this as the expression value)
        my $call_end = Chalk::IR::Node::CallEnd->new(
            call => $call,
        );

        return $call_end;
    }
}

1;
