# ABOUTME: Phase 1a Batch 2 — TDD rig tests for C1-C5 (assignments) and K1-K2 (increment).
# ABOUTME: Each test asserts run_entry(TAG) returns PASS after hand graphs are authored.
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

# --- C1: simple reassignment ---
# class C { method m() { my $x = 1; $x = 2; return $x; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('C1', $spec) };
    ok(!$@, "C1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'C1: verdict is PASS');
        is($result->{P}->return_values->[0], 2, 'C1: returns 2');
    }
}

# --- C2: compound assignment +=  ---
# class C { method m() { my $x = 1; $x += 2; return $x; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('C2', $spec) };
    ok(!$@, "C2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'C2: verdict is PASS');
        is($result->{P}->return_values->[0], 3, 'C2: returns 3');
    }
}

# --- C3: string concat assign .=  ---
# class C { method m() { my $s = "a"; $s .= "b"; return $s; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('C3', $spec) };
    ok(!$@, "C3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'C3: verdict is PASS');
        is($result->{P}->return_values->[0], 'ab', 'C3: returns ab');
    }
}

# --- C4: array element assignment ---
# class C { method m() { my @a = (1); $a[0] = 2; return $a[0]; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('C4', $spec) };
    ok(!$@, "C4: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'C4: verdict is PASS');
        is($result->{P}->return_values->[0], 2, 'C4: returns 2');
    }
}

# --- C5: hash element assignment ---
# class C { method m() { my %h = (); $h{k} = 1; return $h{k}; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('C5', $spec) };
    ok(!$@, "C5: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'C5: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'C5: returns 1');
    }
}

# --- K1: pre-increment ---
# class C { method m() { my $i = 0; ++$i; return $i; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('K1', $spec) };
    ok(!$@, "K1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'K1: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'K1: returns 1');
    }
}

# --- K2: post-increment ---
# class C { method m() { my $i = 0; $i++; return $i; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('K2', $spec) };
    ok(!$@, "K2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'K2: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'K2: returns 1');
    }
}

done_testing();
