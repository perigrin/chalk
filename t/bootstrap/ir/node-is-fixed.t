# ABOUTME: Effectfulness is a property of the NODE TYPE, not a lookup in a name registry.
# ABOUTME: is_fixed must agree with %STATEMENT_EFFECT_OPS everywhere the registry is right.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;

# ---------------------------------------------------------------------------
# %STATEMENT_EFFECT_OPS is a registry of ten op NAMES held beside the node
# classes. There are 86 node classes and none of them declares whether it has an
# effect, so every consumer answers the question by string lookup -- 96 op-name
# string comparisons over 19 distinct ops across lib/.
#
# The prior-art survey (docs/research/2026-08-13-branch-merge-prior-art.md)
# found that production Sea-of-Nodes compilers make this a TYPE property: in
# Graal an effectful node IS a FixedNode, which is why its diamond-collapse test
# degenerates to "is the arm empty?" -- the side-effect question is subsumed
# structurally and never asked. Chalk cannot take that shortcut while the answer
# lives in a name list.
#
# This is step one: put the answer on the type. The registry stays for now, and
# these tests pin that the two AGREE -- so the registry can be deleted later
# without changing behaviour, and so any disagreement surfaces as a failing test
# rather than as a miscompile.
# ---------------------------------------------------------------------------

my $f = Chalk::IR::NodeFactory->new;

# A node of each effectful op, built minimally. The point is the TYPE, so the
# inputs only need to satisfy the constructor.
sub const ($v) {
    return $f->make('Constant', value => $v, const_type => 'integer');
}

subtest 'every node answers is_fixed' => sub {
    my $n = const(1);
    can_ok($n, 'is_fixed');
    ok(!$n->is_fixed, 'a Constant is not fixed -- it is a pure value');
};

subtest 'the effectful ops report is_fixed' => sub {
    # Print: a statement effect in any context.
    my $p = $f->make('Print', inputs => [const(1)]);
    ok($p->is_fixed, 'Print is fixed');

    # Assign: a store.
    my $a = $f->make('Assign', inputs => [const(1), const(2)]);
    ok($a->is_fixed, 'Assign is fixed');

    # Call: may do anything.
    my $c = $f->make('Call', inputs => [const(1)],
                     dispatch_kind => 'builtin', name => 'exit');
    ok($c->is_fixed, 'Call is fixed');
};

# THE GAP THIS EXISTS TO CLOSE. Unwind is `die`: it ABORTS. It is absent from
# %STATEMENT_EFFECT_OPS, and the backend compensates with two hand-written
# `eq 'Unwind'` special cases. A collapse pass that consulted the registry would
# judge a die-only arm effect-free and fold it into a select -- the exact
# miscompile class this session has been closing.
subtest 'Unwind is fixed even though the REGISTRY omits it' => sub {
    my $u = $f->make('Unwind', inputs => [const(1)]);
    ok($u->is_fixed, 'Unwind is fixed -- a die aborts, whatever the registry says');

    ok(!$Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS{'Unwind'},
        'and the registry indeed omits it (this is the gap, not a typo)');
};

# Pure values must NOT be fixed, or a collapse pass would never fire.
subtest 'pure value ops are not fixed' => sub {
    for my $op (qw(Add Subtract Multiply Length Not)) {
        my $n = eval { $f->make($op, inputs => [const(1), const(2)]) };
        next unless $n;   # arity differs per op; skip what will not build
        ok(!$n->is_fixed, "$op is not fixed");
    }
};

# The agreement check: for every op the registry NAMES, the type must agree.
# Where they disagree, the registry is what gets corrected -- but the
# disagreement must be visible, not silent.
#
# Each op gets whatever constructor params its class REQUIRES. A subtest that
# pass()es when construction fails would report agreement it never checked --
# the whole point is that every named op is actually exercised, so a
# construction failure is a FAILURE, not a skip.
my %EXTRA_PARAMS = (
    Call           => { dispatch_kind => 'builtin', name => 'exit' },
    CompoundAssign => { op => '+=' },
    RegexSubst     => { replacement => 'y' },
);

subtest 'is_fixed agrees with the registry on every op the registry names' => sub {
    my @named = sort keys %Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS;
    plan tests => scalar @named;

    for my $op (@named) {
        my $n = eval {
            $f->make($op, inputs => [const(1), const(2)],
                     ($EXTRA_PARAMS{$op} // {})->%*);
        };
        ok($n && $n->is_fixed,
            "$op is in the registry AND reports is_fixed" . ($n ? '' : " (CONSTRUCTION FAILED: $@)"));
    }
};

done_testing;
