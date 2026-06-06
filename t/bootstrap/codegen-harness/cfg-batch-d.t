# ABOUTME: Batch D CFG harness tests — M17 (next in loop), M18 (last in loop).
# ABOUTME: Exercises both: jump triggers on some iteration AND correct final result.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness;

my $spec = {
    class       => 'C',
    constructor => { params => {} },
    method      => 'm',
    method_args => [],
    context     => 'scalar',
};

# M17: foreach my $n (1, 2, 3) { next if $n == 2; } return 1;
# The loop runs; next fires on $n==2 (skips $n==2 body, but body is empty).
# Loop completes all iterations and returns 1.
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M17', $spec) };
    ok(!$@, 'M17 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M17 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 1, 'M17 next-in-loop: returns 1 (loop completes)');
    }
}

# M18: foreach my $n (1, 2, 3) { last if $n > 1; } return 1;
# last fires on $n==2 (exits loop early), loop returns 1.
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M18', $spec) };
    ok(!$@, 'M18 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M18 verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 1, 'M18 last-in-loop: returns 1 (loop exits early, method returns 1)');
    }
}

done_testing();
