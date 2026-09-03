# ABOUTME: Stores a value into a capture cell, producing a new memory version.
# ABOUTME: Per-call: two identical writes are two distinct stores, never one.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Value;

class Chalk::IR::Node::CellWrite :isa(Chalk::IR::Value) {

    # inputs[0] is the cell; inputs[1] is the value; inputs[2] is the incoming
    # memory version. The node itself IS the outgoing version -- a later read
    # naming this node observes this write.
    #
    # A CLOSURE WRITES THROUGH TO THE OUTER VARIABLE, measured:
    #
    #   my $n = 5; my $set = sub { $n = shift };
    #   $set->(42);   the enclosing $n is now 42
    #
    # which is why a capture cannot be a value on an edge: there would be
    # nothing for the write to reach.
    method operation() { 'CellWrite' }
    method staleness_kind() { 'opaque' }

    # PER-CALL, for the reason ListAppend is. Two writes of the same value to
    # the same cell are two distinct stores at two distinct program points;
    # merging them drops one, and in a loop that is the difference between
    # incrementing three times and incrementing once.
    #
    # Standing on its own rather than borrowing safety from the memory input
    # hashing apart: that would make this class's correctness depend on
    # another class's identity_kind, and lapse the moment a CellWrite takes a
    # memory input that is not per-call.
    sub identity_kind { 'per_call' }
}
