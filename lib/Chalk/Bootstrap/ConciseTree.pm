# ABOUTME: Ordered list of ConciseOp objects representing an op-tree execution sequence.
# ABOUTME: Provides push_op, concat, rendering as numbered exec lines, and op counting.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::ConciseTree {
    field $ops :param :reader = [];

    # Append a single ConciseOp to the sequence
    method push_op($op) {
        push $ops->@*, $op;
    }

    # Append all ops from another ConciseTree
    method concat($other) {
        push $ops->@*, $other->ops()->@*;
    }

    # Render as numbered exec-order lines like B::Concise -exec output
    method to_exec_string() {
        my @lines;
        for my $i (0 .. $#$ops) {
            my $num = $i + 1;
            push @lines, "$num     " . $ops->[$i]->to_string();
        }
        return join("\n", @lines);
    }

    # Number of ops in the sequence
    method op_count() {
        return scalar $ops->@*;
    }
}
