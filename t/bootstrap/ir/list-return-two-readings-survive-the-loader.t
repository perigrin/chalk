# ABOUTME: A list-returning sub's two readings and a call's context survive the loader.
# ABOUTME: The list face is Return inputs[0]; the scalar face is inputs[1]; Call carries want.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::IR::Serialize::JSON;

# A sub returning a list has TWO readings, and which one the caller gets is
# decided by the CALLER's context -- the callee is compiled once and cannot
# see it (perl leaves entersub's context slot empty for a call in last-operand
# position; `wantarray` is a runtime function for exactly this reason).
#
# So the producer emits both faces unconditionally (perl5-son 802c655):
#
#   Return inputs[0]   the LIST reading: all N values, flattened
#   Return inputs[1]   the SCALAR reading: the last operand read in scalar
#                      context -- a Count of it when that operand is an
#                      aggregate, otherwise its own value
#
# and states each callsite's own context as Call.want.
#
# THE COLLAPSE RULE IS NOT "last element" AND NOT "count". Measured against
# perl 5.42.0:
#
#   sub f { return (10,20,30) }             my $s = f()  -> 30   last operand
#   sub f { my @a=(10,20,30); return @a }   my $s = f()  ->  3   the COUNT
#   sub f { my @x=(10,20); return (99,@x) } my $s = f()  ->  2   @x's LENGTH
#
# The third is the discriminating case: `elements[len-1]` gives 20 where perl
# gives 2. A probe set without it cannot tell the two rules apart -- both
# authors of this wire initially had the rule wrong, and both wrong versions
# agreed with perl on the first two.

my $FIXTURE = 't/bootstrap/ir/data/list-return.json';

my $wire = do {
    open my $fh, '<', $FIXTURE or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);

sub returns_of {
    my ($graph) = @_;
    return grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
    } $graph->nodes->@*;
}

# The fixture's three subs. All three carry TWO readings, and `agg` is the
# case that says why: `return @a` does NOT return a container.
#
#   my @l = agg()   3 elements     the array flattens, like any list return
#   my $s = agg()   3              the COUNT, not the container
#   return \@a      an ARRAY ref   the ONLY way a container survives a return
#
# An earlier producer skipped the flatten for a SINGLE operand, so agg kept
# its operand's Array stamp and carried one reading. THIS TEST ASSERTED THAT
# AS AN INVARIANT ("a bare aggregate answers both readings") -- encoding a
# producer bug as a rule about perl. Return position imposes list context on
# its operand exactly as `(99,@x)` does, so agg needs a scalar face (a Count)
# like every other list return.
#
# What this file exists to pin is unaffected: distinguishing value() from
# inputs[-1] needs A Return with two inputs, not a Return with one.
my %expect_inputs = (
    'main::lit' => 2,   # return (10,20,30)      -- list literal
    'main::agg' => 2,   # my @a=(...); return @a -- flattens; Count is the face
    'main::mix' => 2,   # return (99,@x)         -- mixed
);

subtest 'both readings survive, and only where a second reading exists' => sub {
    for my $name (sort keys %expect_inputs) {
        my $graph = $graphs->{$name};
        ok($graph, "$name present in the loaded wire") or next;

        my @returns = returns_of($graph);
        is(scalar(@returns), 1, "$name has exactly one Return");

        my $ret = $returns[0] or next;
        is(scalar($ret->inputs->@*), $expect_inputs{$name},
            "$name Return carries $expect_inputs{$name} input(s)");

        # value() is the LIST reading and must be inputs[0] -- never the last
        # input. Those coincide at arity 1 and diverge at arity 2, which is
        # precisely the shape that broke three sites in this repo.
        is($ret->value(), $ret->inputs->[0],
            "$name value() is inputs[0], the list reading");

        if ($expect_inputs{$name} == 2) {
            isnt($ret->value(), $ret->inputs->[-1],
                "$name list reading is NOT the last input");
            ok(defined $ret->scalar_value(),
                "$name has a scalar face");
            is($ret->scalar_value(), $ret->inputs->[1],
                "$name scalar_value() is inputs[1]");
        }
        else {
            ok(!defined $ret->scalar_value(),
                "$name has NO scalar face");
        }
    }
};

# Call.want is the callsite's own context. UNDEF IS A REAL STATE, not missing
# data: perl leaves entersub's context slot empty for a call in last-operand
# position, because that context arrives at runtime from the caller's frame
# (`entersub KS` -- bare K, against `sKS`/`lKS` for a call whose context is
# static). A consumer that cannot tell undef from "producer said nothing" gets
# that case backwards.
subtest 'a callsite carries its own context' => sub {
    my $prog = $graphs->{'main::__PROGRAM__'};
    ok($prog, 'program graph present') or return;

    my %want_by_call;
    for my $n ($prog->nodes->@*) {
        next unless blessed($n) && $n->can('operation') && $n->operation eq 'Call';
        next unless $n->can('name') && defined $n->name;
        push $want_by_call{ $n->name }->@*, $n->want;
    }

    # The fixture calls lit() twice -- once in scalar context, once in list --
    # and mix() in void context. ASSERT THE THREE ARE DISTINCT rather than
    # asserting each has a value: a per-call check passes when every call
    # reports the same thing, which is exactly the bug that would make `want`
    # worthless. (The sort_cmp test in this directory makes the same argument.)
    my @lit = sort grep { defined } ($want_by_call{'main::lit'} // [])->@*;
    is_deeply(\@lit, ['list', 'scalar'],
        'lit() is called in BOTH list and scalar context, and they differ');

    is_deeply($want_by_call{'main::mix'}, ['void'],
        'mix() in void context');
};

done_testing;
