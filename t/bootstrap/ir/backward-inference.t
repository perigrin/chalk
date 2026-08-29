# ABOUTME: Backward inference fills a hole from a use site -- and never
# ABOUTME: preempts a node whose type has an authoritative source elsewhere.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

# Real nodes, not duck-types: Chalk::IR::Value is a `feature class`, which
# cannot be subclassed through @ISA, and the pass gates its store on ->isa of
# it. A bless-based fake silently fails that gate and every store is skipped.
use Chalk::IR::NodeFactory;

require Chalk::IR::Transform::BackwardInference;
my $B = 'Chalk::IR::Transform::BackwardInference';

subtest 'the rule: only a slot read with no other source is inferable' => sub {
    # THE load-bearing assertion. A Call's type is its callee's return type; a
    # Subscript's is its container's element type; a Phi's is the join of its
    # arms. Letting a use site decide any of those is how the producer shipped
    # a miscompile (a Call stamped Num from its CALLER's requirement, asserting
    # a return type the callee did not have).
    my %open   = map { $_ => 1 } qw(PadAccess FieldAccess Parameter);
    my @closed = qw(Call Subscript Phi Add Assign Concat TernaryExpr Ref);

    for my $op (sort keys %open) {
        ok($B->can('_is_backward_inferable'), 'helper exists') if 0;
        ok(Chalk::IR::Transform::BackwardInference::_is_backward_inferable(
               _fake_node($op)),
           "$op IS backward-inferable (a slot read, no other source)");
    }
    for my $op (@closed) {
        ok(!Chalk::IR::Transform::BackwardInference::_is_backward_inferable(
               _fake_node($op)),
           "$op is NOT -- it has an authoritative source elsewhere");
    }
};

subtest 'a Coerce is transparent to a requirement' => sub {
    # `$s . "!"` has the Concat consuming a Coerce, not $s. Without threading,
    # the requirement stops at a node that is already Str and the value beneath
    # -- the one with no forward seed -- never gets typed.
    my $inner = _fake_node('PadAccess');
    my $c1    = _fake_node('Coerce', [$inner]);
    my $c2    = _fake_node('Coerce', [$c1]);
    is(Chalk::IR::Transform::BackwardInference::_thread_through_coerce($c2),
       $inner, 'descends a Coerce chain to the value underneath');
    is(Chalk::IR::Transform::BackwardInference::_thread_through_coerce($inner),
       $inner, 'and is a no-op on a non-Coerce');
};

subtest 'a slot read declares Scalar; a Parameter declares nothing' => sub {
    my $d = \&Chalk::IR::Transform::BackwardInference::_declared_slot_type;
    is($d->(_fake_node('PadAccess')),   'Scalar', 'PadAccess declares Scalar');
    is($d->(_fake_node('FieldAccess')), 'Scalar', 'FieldAccess declares Scalar');
    is($d->(_fake_node('Parameter')),   undef,
       'Parameter declares nothing -- it takes the requirement directly');
};

# A minimal duck-typed node: the pass only calls ->operation and ->inputs on
# these paths, so a real Chalk::IR::Node is not needed to pin the rules.
sub _fake_node ($op, $inputs = []) {
    return bless { op => $op, in => $inputs }, 'BackwardInferenceTest::Node';
}

package BackwardInferenceTest::Node {
    sub operation { $_[0]{op} }
    sub inputs    { $_[0]{in} }
}

subtest 'termination is PROVEN, not capped' => sub {
    my $src = do {
        open my $fh, '<', 'lib/Chalk/IR/Transform/BackwardInference.pm'
            or die "BackwardInference.pm: $!";
        local $/; <$fh>;
    };

    # Kildall's store discipline, in the DESCENDING direction. This pass MEETS
    # rather than joins, so its chain descends -- Scalar -> Str -> Num -> Int --
    # but the two requirements are the same: fold the old value into the new,
    # and write only on an actual change. With both, the chain is strictly
    # monotone in a lattice of height ~6 and the loop must halt on its own.
    like($src, qr/next if defined \$prev && \$prev eq \$result/,
         'the write is guarded on an actual move');
    like($src, qr/for my \$src \(\$declared, \$node->stamp\)/,
         'and the node\'s OWN stamp is one of the sources folded into the meet');

    # The round cap may REMAIN as a belt -- what must not remain is termination
    # DEPENDING on it, which would silently truncate inference rather than
    # reaching a fixpoint.
    like($src, qr/last unless \$changed/,
         'the loop still exits on quiescence, which is the real proof');
};

subtest 'a hole is filled once, and a filled hole is never revisited' => sub {
    # What actually bounds this pass is the `Unknown` gate at the top of the
    # node loop: it only ever touches a node whose stamp is literally
    # 'Unknown', and filling one removes it from consideration for good. So
    # each node moves at most ONCE and the loop is bounded by the number of
    # holes, not by the round cap.
    #
    # NOTE this is a WEAKER property than the fold+guard discipline the
    # subtest above pins in source. The two are complementary and neither
    # subsumes the other: mutating away either half of the discipline leaves
    # THIS subtest green, because a write-once pass cannot expose a sideways
    # move. The discipline is what keeps that true if the `Unknown` gate is
    # ever loosened -- which is exactly what an optimistic (CCP-style) phase
    # for recursive calls would have to do.
    my $f   = Chalk::IR::NodeFactory->new;
    my $pad = $f->make('PadAccess', targ => 0, varname => '$s', inputs => []);
    my $cat = $f->make('Concat', inputs => [$pad, $pad]);
    my $g   = TerminationTest::Graph->new([$pad, $cat]);

    # The pass only touches holes, and a hole is the literal stamp 'Unknown'
    # -- which is what the loader writes for an untyped node.
    $pad->set_stamp('Unknown');

    my $writes = 0;
    my $real   = Chalk::IR::Node->can('set_stamp');
    no warnings 'redefine';
    local *Chalk::IR::Node::set_stamp = sub { $writes++; goto &$real };

    my $stamped = Chalk::IR::Transform::BackwardInference::run({ main => $g });

    is($pad->stamp, 'Str', 'settles at meet(Scalar, Str) = Str');
    is($writes, 1, 'and writes exactly once');
    is($stamped, 1, 'reports the one stamp it actually made');

    # Idempotence: a settled graph has no holes left, so a second run is a
    # complete no-op. This is the property the round cap must never be doing.
    my $again = Chalk::IR::Transform::BackwardInference::run({ main => $g });
    is($again, 0, 'a second run over a settled graph stamps nothing');
    is($writes, 1, 'and does not write again');
};

package TerminationTest::Graph {
    sub new { my ($class, $nodes) = @_; return bless { nodes => $nodes }, $class }
    sub nodes { $_[0]{nodes} }
}

subtest 'exhausting the round cap is LOUD, never a silent truncation' => sub {
    # The cap must never be the thing that ends the loop: if it were, holes
    # would be left unfilled with no signal at all -- inference silently
    # truncated. Forcing a node to keep moving proves the die fires rather
    # than the loop quietly running out.
    my $f   = Chalk::IR::NodeFactory->new;
    my $pad = $f->make('PadAccess', targ => 0, varname => '$s', inputs => []);
    my $cat = $f->make('Concat', inputs => [$pad, $pad]);
    my $g   = TerminationTest::Graph->new([$pad, $cat]);
    $pad->set_stamp('Unknown');

    # Simulate a non-settling stamp: something downstream keeps resetting the
    # node to a hole, so it is reconsidered every round and never quiesces.
    no warnings 'redefine';
    my $real = Chalk::IR::Node->can('set_stamp');
    local *Chalk::IR::Node::set_stamp = sub { $real->($_[0], 'Unknown') };

    my $err;
    eval { Chalk::IR::Transform::BackwardInference::run({ main => $g }); 1 }
        or $err = $@;

    like($err, qr/did not reach a fixpoint/,
         'the pass dies rather than returning a half-inferred graph');
};

done_testing;
