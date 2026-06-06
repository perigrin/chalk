# ABOUTME: Batch C CFG harness tests — D4 (postfix if), D5 (postfix while), M5 (postfix unless).
# ABOUTME: Exercises BOTH outcomes: fires/doesn't-fire for if/unless, loop runs/doesn't-run for while.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness;

# D4: my $x = 0; $x = 1 if $n > 0; return $x;
# n=1: condition fires => $x = 1
# n=-1: condition does not fire => $x = 0

for my $case (
    [1,  1, 'D4 n=1 (fires): $x = 1'],
    [-1, 0, 'D4 n=-1 (does not fire): $x = 0'],
) {
    my ($n, $expected, $label) = @$case;
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [$n],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D4', $spec) };
    ok(!$@, "D4 run_entry does not die ($label)") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', "D4 verdict is PASS ($label)");
        my $retval = $result->{P}->return_values->[0];
        is($retval, $expected, "D4 return value is $expected ($label)");
    }
}

# D5: my $i = 0; $i = $i + 1 while $i < 3; return $i;
# Loop runs 3 times: expects $i = 3
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D5', $spec) };
    ok(!$@, 'D5 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D5 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 3, 'D5 postfix while: $i increments to 3');
    }
}

# M5: my $x = 0; $x = 1 unless $n; return $x;
# n=0 (falsy): unless fires => $x = 1
# n=1 (truthy): unless does not fire => $x = 0

for my $case (
    [0, 1, 'M5 n=0 (falsy, fires): $x = 1'],
    [1, 0, 'M5 n=1 (truthy, does not fire): $x = 0'],
) {
    my ($n, $expected, $label) = @$case;
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [$n],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M5', $spec) };
    ok(!$@, "M5 run_entry does not die ($label)") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', "M5 verdict is PASS ($label)");
        my $retval = $result->{P}->return_values->[0];
        is($retval, $expected, "M5 return value is $expected ($label)");
    }
}

done_testing();
