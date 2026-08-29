# ABOUTME: Backward inference fills a hole from a use site -- and never
# ABOUTME: preempts a node whose type has an authoritative source elsewhere.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

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

done_testing;
