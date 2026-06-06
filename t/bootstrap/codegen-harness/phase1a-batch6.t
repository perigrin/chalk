# ABOUTME: Phase 1a Batch 6 — TDD rig tests for H1-H4 (map/grep/sort/anon-sub).
# ABOUTME: Block bodies are plain statement arrays in AnonSub inputs[1] per the emitter.
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

# --- H1: map block ---
# class C { method m() { my @r = map { $_ * 2 } (1, 2, 3); return scalar @r; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('H1', $spec) };
    ok(!$@, "H1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'H1: verdict is PASS');
        is($result->{P}->return_values->[0], 3, 'H1: returns 3 (mapped list length)');
    }
}

# --- H2: grep block ---
# class C { method m() { my @r = grep { $_ > 1 } (1, 2, 3); return scalar @r; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('H2', $spec) };
    ok(!$@, "H2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'H2: verdict is PASS');
        is($result->{P}->return_values->[0], 2, 'H2: returns 2 (grep matches: 2,3)');
    }
}

# --- H3: sort ---
# class C { method m() { my @r = sort (3, 1, 2); return $r[0]; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('H3', $spec) };
    ok(!$@, "H3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'H3: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'H3: returns 1 (first sorted element)');
    }
}

# --- H4: anonymous sub ---
# class C { method m() { my $f = sub ($x) { return $x + 1; }; return $f->(1); } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('H4', $spec) };
    ok(!$@, "H4: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'H4: verdict is PASS');
        is($result->{P}->return_values->[0], 2, 'H4: returns 2 (f.(1) = 1+1)');
    }
}

done_testing();
