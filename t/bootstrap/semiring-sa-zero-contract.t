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

done_testing;
