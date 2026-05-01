# ABOUTME: Verifies SemanticAction.zero() honors the (Context, Context) -> Context contract.
# ABOUTME: Per Decision 4 in 2026-04-24-semiring-contract-drift.md, SA-zero is the cheapest violator to migrate.
use 5.42.0;
use utf8;
use Test::More;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;

my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

subtest 'zero() returns a Context, not undef' => sub {
    my $z = $sa->zero();

    ok(defined $z, 'zero() returns a defined value');
    isa_ok($z, 'Chalk::Bootstrap::Context');
    ok($z->is_zero, 'zero() Context has is_zero flag set to true');
};

subtest 'is_zero() agrees with Context is_zero flag' => sub {
    my $z   = $sa->zero();
    my $one = $sa->one();

    ok($sa->is_zero($z),   'is_zero($zero) is true');
    ok(!$sa->is_zero($one),'is_zero($one)  is false');
};

subtest 'multiply propagates zero through Context (left and right)' => sub {
    my $z   = $sa->zero();
    my $one = $sa->one();

    my $left_zero  = $sa->multiply($z,   $one);
    my $right_zero = $sa->multiply($one, $z);

    isa_ok($left_zero,  'Chalk::Bootstrap::Context', 'left-zero multiply result');
    isa_ok($right_zero, 'Chalk::Bootstrap::Context', 'right-zero multiply result');
    ok($left_zero->is_zero,  'multiply(zero, one) is_zero');
    ok($right_zero->is_zero, 'multiply(one, zero) is_zero');
};

subtest 'add of zero with non-zero returns the non-zero survivor' => sub {
    # Note: SA's add() returns an arrayref of survivors by design (per
    # 2026-04-24-semiring-contract-drift.md, this is outside Decision 4's
    # zero/one/multiply contract). Verify zero gets dropped from survivors.
    my $z   = $sa->zero();
    my $one = $sa->one();

    my $left_add  = $sa->add($z,   $one);
    my $right_add = $sa->add($one, $z);

    is(ref $left_add,  'ARRAY', 'add(zero, one) returns arrayref');
    is(ref $right_add, 'ARRAY', 'add(one, zero) returns arrayref');
    is(scalar $left_add->@*,  1, 'add(zero, one) drops zero from survivors');
    is(scalar $right_add->@*, 1, 'add(one, zero) drops zero from survivors');
    ok(!$left_add->[0]->is_zero(),  'surviving member from add(zero, one) is non-zero');
    ok(!$right_add->[0]->is_zero(), 'surviving member from add(one, zero) is non-zero');
};

subtest '_complete_sa with zero value short-circuits to zero' => sub {
    # FilterComposite short-circuits zero before _complete_sa is ever called,
    # so the defensive guard at SemanticAction.pm:220 is not exercised on the
    # hot path. Lock the documented behavior anyway.
    my $z = $sa->zero();

    my $result = $sa->_complete_sa($z, 'AnyRule');

    isa_ok($result, 'Chalk::Bootstrap::Context', '_complete_sa($zero, ...) result');
    ok($result->is_zero(), '_complete_sa($zero, ...) returns zero Context');
};

subtest 'on_merge with zero on either side is a no-op' => sub {
    # FilterComposite short-circuits zero before on_merge is ever called,
    # so the defensive guard at SemanticAction.pm:326 is not exercised on the
    # hot path. Lock the documented behavior anyway.
    my $z   = $sa->zero();
    my $one = $sa->one();

    # All three should return without dying or mutating.
    my $r1 = $sa->on_merge($z, $one);
    my $r2 = $sa->on_merge($one, $z);
    my $r3 = $sa->on_merge($z, $z);

    is($r1, undef, 'on_merge($zero, $one) returns undef (no-op)');
    is($r2, undef, 'on_merge($one, $zero) returns undef (no-op)');
    is($r3, undef, 'on_merge($zero, $zero) returns undef (no-op)');
};

done_testing;
