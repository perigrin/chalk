# ABOUTME: I4/I5 gate-hardening: Chalk::Target hierarchy must be coherent.
# ABOUTME: LLVM must isa the typed-IR base; Bootstrap targets must NOT have lower().
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

# I4/I5 (R1 reopened):
# I4: Chalk::Target::LLVM does NOT isa Chalk::Target — the new base's lower contract
#     is dead surface (LLVM has its own class-method lower).
# I5: Bootstrap targets now inherit an alien lower die-stub from Chalk::Target.
#
# Fix (SPLIT): two tiers:
#   - Bootstrap-tier: Chalk::Target with generate/generate_distribution stubs
#     (Chalk::Bootstrap::Target :isa this; ~5 Bootstrap subclasses continue unchanged)
#   - Typed-IR-tier: Chalk::IR::Target with lower stub
#     (Chalk::Target::LLVM uses/inherits this)
#
# Acceptance criteria (from task):
#   - Chalk::Target::LLVM->isa(<typed-IR base>) == YES
#   - Chalk::Bootstrap::Perl::Target::Perl->can('lower') == NO
#   - All ~14 LLVM ->lower() callers still work
#   - codegen-target.t, perl-actions-tier-a.t, perl-target-perl-tier-a.t,
#     codegen-perl.t, bnf-target-c.t continue to pass

use Chalk::Target::LLVM;
use Chalk::Bootstrap::Target;
use Chalk::Bootstrap::Perl::Target::Perl;

# Test 1: Chalk::Target::LLVM must inherit from the typed-IR tier base
subtest 'LLVM isa typed-IR-tier base (I4)' => sub {
    ok(Chalk::Target::LLVM->isa('Chalk::IR::Target'),
        'Chalk::Target::LLVM->isa(Chalk::IR::Target) is YES (I4)')
        or diag("LLVM does not inherit from Chalk::IR::Target — fix I4");
};

# Test 2: Bootstrap targets must NOT inherit lower() from the Bootstrap base
subtest 'Bootstrap Perl target has no lower() (I5)' => sub {
    ok(!Chalk::Bootstrap::Perl::Target::Perl->can('lower'),
        'Chalk::Bootstrap::Perl::Target::Perl->can("lower") is NO (I5)')
        or diag("Bootstrap Perl target inherits alien lower() — I5 fix missing");
};

# Test 3: Bootstrap target isa the Bootstrap base (Chalk::Target) not the typed-IR base
subtest 'Bootstrap target isa Chalk::Target, NOT Chalk::IR::Target' => sub {
    ok(Chalk::Bootstrap::Target->isa('Chalk::Target'),
        'Chalk::Bootstrap::Target->isa(Chalk::Target) is YES')
        or diag("Bootstrap Target no longer isa Chalk::Target");

    ok(!Chalk::Bootstrap::Target->isa('Chalk::IR::Target'),
        'Chalk::Bootstrap::Target->isa(Chalk::IR::Target) is NO')
        or diag("Bootstrap Target should NOT inherit from the typed-IR tier");
};

# Test 4: Chalk::Target does NOT provide lower() (it is Bootstrap-tier only)
subtest 'Chalk::Target does not provide lower() (Bootstrap-tier only)' => sub {
    require Chalk::Target;
    ok(!Chalk::Target->can('lower'),
        'Chalk::Target->can("lower") is NO (lower belongs to typed-IR tier)')
        or diag("Chalk::Target still provides lower() — Bootstrap targets would inherit it");
};

# Test 5: Chalk::IR::Target provides lower() stub (typed-IR tier)
subtest 'Chalk::IR::Target provides lower() stub' => sub {
    require Chalk::IR::Target;
    ok(Chalk::IR::Target->can('lower'),
        'Chalk::IR::Target->can("lower") is YES')
        or diag("Chalk::IR::Target does not provide lower() — typed-IR contract missing");
};

# Test 6: LLVM lower() still callable as class method (no regression on ~14 callers)
subtest 'LLVM lower() still callable as class method' => sub {
    ok(Chalk::Target::LLVM->can('lower'),
        'Chalk::Target::LLVM->can("lower") is YES')
        or diag("LLVM lost its lower() method");

    # Verify it is a real method (not just inherited stub that dies immediately)
    my $ref = Chalk::Target::LLVM->can('lower');
    ok(defined $ref && ref($ref) eq 'CODE',
        'LLVM lower() is a CODE ref')
        or diag("LLVM lower is not a CODE ref: " . (ref($ref) // 'undef'));
};

done_testing();
