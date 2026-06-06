# ABOUTME: Phase 1a Batch 5 — TDD rig tests for L1-L4 (logical ops), D6 (ternary), J1-J3 (regex/qw).
# ABOUTME: D6, L1-L4 take parameters passed via spec constructor params.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness;

# D6: class C { method m($n) { my $x = $n > 0 ? 1 : 2; return $x; } }
# Pass n=1 to get $x=1, n=-1 to get $x=2
{
    my $spec_pos = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [1],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D6', $spec_pos) };
    ok(!$@, "D6: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D6: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'D6: returns 1 when n=1');
    }
}

# L1: logical and — return $a && $b
# Pass a=1, b=2 -> returns 2 (last truthy value)
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [1, 2],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L1', $spec) };
    ok(!$@, "L1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L1: verdict is PASS');
        is($result->{P}->return_values->[0], 2, 'L1: returns 2 (last truthy)');
    }
}

# L2: logical or — return $a || $b
# Pass a=0, b=3 -> returns 3
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [0, 3],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L2', $spec) };
    ok(!$@, "L2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L2: verdict is PASS');
        is($result->{P}->return_values->[0], 3, 'L2: returns 3');
    }
}

# L3: defined-or — return $a // $b
# Pass a=undef, b=4 -> returns 4
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [undef, 4],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L3', $spec) };
    ok(!$@, "L3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L3: verdict is PASS');
        is($result->{P}->return_values->[0], 4, 'L3: returns 4');
    }
}

# L4: not — return !$a
# Pass a=0 -> returns 1 (truthy)
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [0],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L4', $spec) };
    ok(!$@, "L4: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L4: verdict is PASS');
    }
}

# J1: regex match — return $s =~ /foo/
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => ['foobar'],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('J1', $spec) };
    ok(!$@, "J1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'J1: verdict is PASS');
    }
}

# J2: regex substitution — $s =~ s/foo/bar/; return $s
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => ['foobar'],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('J2', $spec) };
    ok(!$@, "J2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'J2: verdict is PASS');
        is($result->{P}->return_values->[0], 'barbar', 'J2: returns barbar after substitution');
    }
}

# J3: qw literal — my @keys = qw(a b c); return scalar @keys
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('J3', $spec) };
    ok(!$@, "J3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'J3: verdict is PASS');
        is($result->{P}->return_values->[0], 3, 'J3: returns 3 (qw list length)');
    }
}

done_testing();
