# ABOUTME: Allocates a capture cell -- the heap location a closure shares with its enclosing scope.
# ABOUTME: Per-call: one MakeCell site executing N times yields N distinct cells.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Value;

class Chalk::IR::Node::MakeCell :isa(Chalk::IR::Value) {

    # inputs[0] is the initial value; inputs[1] is the incoming memory version.
    #
    # A CAPTURE IS A CELL, NOT A VALUE. Measured against perl 5.42.0:
    #
    #   my $n = 5; my $c = sub { $n }; $n = 99;   $c->() is 99
    #   my $n = 5; my $set = sub { $n = shift };  the write reaches the outer $n
    #   $inc and $rd over one $c                  observe each other
    #
    # A value on the closure's input edge would give each closure a SNAPSHOT --
    # right for a read-only capture and silently wrong for all three above. The
    # cell makes the sharing explicit rather than implied, and puts it on the
    # memory chain where the optimizer already models aliasing.
    field $cell_name :param :reader = undef;

    # Whether any closure over this cell WRITES to it. A read-only capture can
    # be lowered as a plain value with no allocation at all.
    #
    # THE CONSERVATIVE DIRECTION IS TRUE. Claiming written when it is not costs
    # an allocation; claiming NOT written when it is drops the write -- a
    # miscompile. The producer classifies this structurally (a TARGMY add
    # carries no OPf_MOD, so a flag test alone reports the canonical mutation
    # `$c = $c + 1` as read-only) and says written whenever it cannot tell.
    field $captured_written :param :reader = 0;

    method operation() { 'MakeCell' }
    method staleness_kind() { 'opaque' }

    # PER-CALL, and this is the whole reason the class exists rather than
    # reusing an existing allocation node.
    #
    # `for my $i (1..3) { push @subs, sub { $i } }` prints 1,2,3 -- ONE
    # MakeCell node, THREE executions, THREE cells. Hash-consing collapses two
    # textually identical allocations into one, so every closure shares a cell
    # perl gives them separately and the program prints 3,3,3.
    #
    # ArrayRef already hit exactly this (019eb6ff item 4): `[1,2]` and `[1,2]`
    # are two distinct arrays, and hash-consing them made one malloc that two
    # "distinct" refs silently aliased.
    sub identity_kind { 'per_call' }
}
