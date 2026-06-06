# ABOUTME: Batch B CFG harness tests — D2 (while), D3 (foreach), M6 (postfix for), M7 (foreach no-my), M25 (C-style for).
# ABOUTME: Exercises loop running through all iterations; verifies accumulated result = perl oracle.
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

# D2: while ($i < 3) { $i = $i + 1; } — expects $i = 3
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D2', $spec) };
    ok(!$@, 'D2 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D2 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 3, 'D2 while loop: $i increments to 3');
    }
}

# D3: foreach my $n (1,2,3) { $sum += $n; } — expects $sum = 6
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D3', $spec) };
    ok(!$@, 'D3 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D3 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 6, 'D3 foreach: sum 1+2+3 = 6');
    }
}

# M6: $sum = $sum + $_ for (1,2,3); — expects $sum = 6
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M6', $spec) };
    ok(!$@, 'M6 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M6 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 6, 'M6 postfix for: sum 1+2+3 = 6');
    }
}

# M7: foreach (1,2,3) { $sum = $sum + $_; } — expects $sum = 6
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M7', $spec) };
    ok(!$@, 'M7 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M7 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 6, 'M7 foreach no-my: sum 1+2+3 = 6');
    }
}

# M25: for (my $i=0; $i<3; $i++) { $sum += $i; } — expects $sum = 0+1+2 = 3
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M25', $spec) };
    ok(!$@, 'M25 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M25 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 3, 'M25 C-style for: sum 0+1+2 = 3');
    }
}

done_testing();
