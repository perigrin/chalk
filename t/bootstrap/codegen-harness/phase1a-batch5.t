# ABOUTME: Phase 1a Batch 5 — TDD rig tests for L1-L4 (logical ops), D6 (ternary), J1-J3 (regex/qw).
# ABOUTME: D6, L1-L4 take parameters passed via spec constructor params.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness;

# D6: class C { method m($n) { my $x = $n > 0 ? 1 : 2; return $x; } }
# Bilateral: n=1 (true branch -> 1) AND n=-1 (false branch -> 2).
{
    # True branch: n=1 -> $x = 1
    my $spec_pos = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [1],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D6', $spec_pos) };
    ok(!$@, "D6 true-branch: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D6 true-branch: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'D6 true-branch: returns 1 when n=1');
    }
}
{
    # False branch: n=-1 -> $x = 2
    my $spec_neg = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [-1],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D6', $spec_neg) };
    ok(!$@, "D6 false-branch: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D6 false-branch: verdict is PASS');
        is($result->{P}->return_values->[0], 2, 'D6 false-branch: returns 2 when n=-1');
    }
}

# L1: logical and — return $a && $b
# Bilateral: (1,2)->2 (both truthy, last wins) AND (0,2)->0 (short-circuit on false left).
{
    # Both truthy: a=1, b=2 -> returns 2 (last truthy value)
    my $spec_tt = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [1, 2],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L1', $spec_tt) };
    ok(!$@, "L1 both-truthy: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L1 both-truthy: verdict is PASS');
        is($result->{P}->return_values->[0], 2, 'L1 both-truthy: returns 2 (last truthy)');
    }
}
{
    # Left false: a=0, b=2 -> short-circuits, returns 0 (falsy)
    my $spec_ft = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [0, 2],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L1', $spec_ft) };
    ok(!$@, "L1 short-circuit: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L1 short-circuit: verdict is PASS');
        is($result->{P}->return_values->[0], 0, 'L1 short-circuit: returns 0 (left false, short-circuit)');
    }
}

# L2: logical or — return $a || $b
# Bilateral: (0,3)->3 (left false, right wins) AND (1,3)->1 (left truthy, left wins).
{
    # Left false: a=0, b=3 -> returns 3 (right wins)
    my $spec_ft = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [0, 3],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L2', $spec_ft) };
    ok(!$@, "L2 left-false: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L2 left-false: verdict is PASS');
        is($result->{P}->return_values->[0], 3, 'L2 left-false: returns 3 (right wins)');
    }
}
{
    # Left truthy: a=1, b=3 -> returns 1 (left wins, right never evaluated)
    my $spec_tt = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [1, 3],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L2', $spec_tt) };
    ok(!$@, "L2 left-truthy: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L2 left-truthy: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'L2 left-truthy: returns 1 (left wins)');
    }
}

# L3: defined-or — return $a // $b
# Bilateral: (undef,4)->4 (left undefined, right wins) AND (5,4)->5 (left defined, left wins).
{
    # Left undef: a=undef, b=4 -> returns 4 (right wins)
    my $spec_undef = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [undef, 4],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L3', $spec_undef) };
    ok(!$@, "L3 left-undef: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L3 left-undef: verdict is PASS');
        is($result->{P}->return_values->[0], 4, 'L3 left-undef: returns 4 (right wins)');
    }
}
{
    # Left defined: a=5, b=4 -> returns 5 (left wins)
    my $spec_def = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [5, 4],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L3', $spec_def) };
    ok(!$@, "L3 left-defined: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L3 left-defined: verdict is PASS');
        is($result->{P}->return_values->[0], 5, 'L3 left-defined: returns 5 (left wins)');
    }
}

# L4: not — return !$a
# Bilateral: (0)->true/1 (false input, negated to true) AND (1)->false/'' (truthy negated).
{
    # False input: a=0 -> !0 = 1 (true)
    my $spec_false = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [0],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L4', $spec_false) };
    ok(!$@, "L4 false-input: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L4 false-input: verdict is PASS');
        ok($result->{P}->return_values->[0], 'L4 false-input: returns truthy (!0)');
    }
}
{
    # True input: a=1 -> !1 = '' (false/empty string)
    my $spec_true = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [1],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('L4', $spec_true) };
    ok(!$@, "L4 true-input: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'L4 true-input: verdict is PASS');
        ok(!$result->{P}->return_values->[0], 'L4 true-input: returns falsy (!1)');
    }
}

# J1: regex match — return $s =~ /foo/
# Bilateral: 'foobar' (match succeeds -> 1) AND 'bazqux' (no match -> '').
{
    # Match succeeds: s='foobar' -> $s =~ /foo/ returns 1
    my $spec_match = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => ['foobar'],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('J1', $spec_match) };
    ok(!$@, "J1 match: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'J1 match: verdict is PASS');
        ok($result->{P}->return_values->[0], 'J1 match: returns truthy when pattern matches');
    }
}
{
    # No match: s='bazqux' -> $s =~ /foo/ returns '' (false)
    my $spec_nomatch = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => ['bazqux'],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('J1', $spec_nomatch) };
    ok(!$@, "J1 no-match: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'J1 no-match: verdict is PASS');
        ok(!$result->{P}->return_values->[0], 'J1 no-match: returns falsy when pattern does not match');
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
