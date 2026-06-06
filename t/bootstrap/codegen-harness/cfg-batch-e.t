# ABOUTME: Batch E CFG harness tests — E2 (return from branch), E3 (return from loop), E4 (die with postfix).
# ABOUTME: Exercises both: early-return/die path and fall-through path where applicable.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness;

# E2: if ($n > 0) { return 1; } return 0;
# n=1 (>0): early return 1
# n=-1 (not >0): falls through to return 0

for my $case (
    [1,  1, 'E2 n=1 (>0): early return 1'],
    [-1, 0, 'E2 n=-1 (not >0): falls through to return 0'],
) {
    my ($n, $expected, $label) = @$case;
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [$n],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('E2', $spec) };
    ok(!$@, "E2 run_entry does not die ($label)") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', "E2 verdict is PASS ($label)");
        my $retval = $result->{P}->return_values->[0];
        is($retval, $expected, "E2 return value is $expected ($label)");
    }
}

# E3: foreach my $n (1, 2, 3) { return $n if $n == 2; } return 0;
# Iterates; on $n==2, returns $n=2 (early return path)
# (Fall-through path: n never equals 2 in our list, but the corpus has 2 in the list)
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('E3', $spec) };
    ok(!$@, 'E3 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'E3 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 2, 'E3 return-from-loop: returns $n=2 (early return on $n==2)');
    }
}

# E4: die "no" if 1; return 1;
# Always dies (condition is 1); both oracle and generated raise die("no").
# Comparator sees matching exceptions => PASS.
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('E4', $spec) };
    ok(!$@, 'E4 run_entry does not die (harness itself)') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 1 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'E4 verdict is PASS (matching die exceptions)');
    }
}

done_testing();
