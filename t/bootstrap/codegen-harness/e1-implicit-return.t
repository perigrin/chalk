# ABOUTME: Focused regression test for E1 (implicit-return idiom) miscompile fix.
# ABOUTME: Asserts run_entry('E1') yields PASS: generated code returns 1, not '$x'.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness;

my $spec = {
    class       => 'C',
    constructor => { params => {} },
    method      => 'm',
    method_args => [],
    context     => 'scalar',
};

# --- T1: run_entry does not die for E1 ---
my $result = eval { Chalk::CodeGen::Harness->run_entry('E1', $spec) };
is($@, '', 'run_entry("E1") does not die');
ok(defined $result, 'run_entry("E1") returns a defined result');

SKIP: {
    skip 'no result from run_entry', 6 unless defined $result;

    ok(defined $result->{S},       'E1: oracle record S is present');
    ok(defined $result->{P},       'E1: generated record P is present');
    ok(defined $result->{verdict}, 'E1: verdict is present');

    # --- T2: Oracle S returns 1 ---
    my $rv_s = $result->{S}->return_values;
    is($rv_s->[0], 1, 'E1: oracle S return value is 1');

    # --- T3: Generated P must NOT emit a single-quoted string literal '$x' ---
    # Before the fix, the emitter produced `'$x';` (single-quoted) instead of `$x;`
    # which caused the generated code to return the string '$x' instead of 1.
    # We verify the verdict is PASS (P also returns 1), which proves the generated
    # code contains the bare variable $x, not the string literal '$x'.
    is($result->{verdict}{verdict}, 'PASS',
        'E1: end-to-end verdict is PASS (generated code returns 1, not the string "$x")');
}

done_testing();
