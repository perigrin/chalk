# ABOUTME: D1 CFG spike — if/else with reassignment, end-to-end via scheduler path.
# ABOUTME: Exercises BOTH branches (n=1 takes true branch, n=-1 takes false branch); bilateral coverage.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness;

# D1: class C { method m($n) { my $x = 0; if ($n > 0) { $x = 1; } else { $x = 2; } return $x; } }
# True branch: $n=1 > 0 => $x = 1; return 1.
# False branch: $n=-1 not > 0 => $x = 2; return 2.

# --- D1 true branch: n=1 ---
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [1],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D1', $spec) };
    ok(!$@, 'D1 true-branch: run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D1 true-branch: verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 1, 'D1 true-branch: generated code returns 1 (true branch: $x = 1)');
    }
}

# --- D1 false branch: n=-1 ---
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [-1],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D1', $spec) };
    ok(!$@, 'D1 false-branch: run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D1 false-branch: verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 2, 'D1 false-branch: generated code returns 2 (false branch: $x = 2)');
    }
}

done_testing();
