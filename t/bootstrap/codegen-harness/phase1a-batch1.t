# ABOUTME: Phase 1a Batch 1 — TDD rig tests for A2 (array literal VarDecl) and A3 (hash literal VarDecl).
# ABOUTME: Each test asserts run_entry(TAG) returns PASS after hand graphs are authored in HandGraphs.pm.
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

# --- A2: VarDecl array literal ---
# class C { method m() { my @list = (1, 2, 3); return scalar @list; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('A2', $spec) };
    ok(!$@, "A2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'A2: verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 3, 'A2: generated code returns 3 (length of list)');
    }
}

# --- A3: VarDecl hash literal ---
# class C { method m() { my %h = (a => 1, b => 2); return $h{a}; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('A3', $spec) };
    ok(!$@, "A3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'A3: verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 1, 'A3: generated code returns 1 (hash value for key a)');
    }
}

done_testing();
