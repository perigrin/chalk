# ABOUTME: Batch A CFG harness tests — D7 (nested if/else), M16 (block unless).
# ABOUTME: Exercises BOTH branches for each idiom (bilateral coverage).
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness;

# D7: class C { method m($n) { my $x = 0; if ($n > 0) { if ($n > 5) { $x = 1; } else { $x = 2; } } else { $x = 3; } return $x; } }
# n=10 > 5 => outer-true / inner-true => $x = 1
# n=3 > 0 but not > 5 => outer-true / inner-false => $x = 2
# n=-1 not > 0 => outer-false => $x = 3

for my $case (
    [10, 1, 'D7 n=10 (nested-true): $x = 1'],
    [3,  2, 'D7 n=3 (outer-true / inner-false): $x = 2'],
    [-1, 3, 'D7 n=-1 (outer-false): $x = 3'],
) {
    my ($n, $expected, $label) = @$case;
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [$n],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D7', $spec) };
    ok(!$@, "D7 run_entry does not die ($label)") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', "D7 verdict is PASS ($label)");
        my $retval = $result->{P}->return_values->[0];
        is($retval, $expected, "D7 return value is $expected ($label)");
    }
}

# M16: class C { method m($n) { unless ($n) { return 0; } return 1; } }
# n=0 (falsy) => enters unless => return 0
# n=1 (truthy) => skips unless => return 1

for my $case (
    [0, 0, 'M16 n=0 (falsy): enters unless => return 0'],
    [1, 1, 'M16 n=1 (truthy): skips unless => return 1'],
) {
    my ($n, $expected, $label) = @$case;
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [$n],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M16', $spec) };
    ok(!$@, "M16 run_entry does not die ($label)") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', "M16 verdict is PASS ($label)");
        my $retval = $result->{P}->return_values->[0];
        is($retval, $expected, "M16 return value is $expected ($label)");
    }
}

done_testing();
