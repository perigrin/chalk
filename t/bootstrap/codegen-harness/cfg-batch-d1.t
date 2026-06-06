# ABOUTME: Batch D1 CFG harness tests — M26 (observable next) and M27 (observable last).
# ABOUTME: Proves loop-jump correctness: the jump must change the result (not green-laundered).
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness;

# Observable-next: foreach 1..5, skip n==3, accumulate sum.
# Correct sum (next fires)  = 1+2+4+5 = 12.
# Miscompile sum (next dropped) = 1+2+3+4+5 = 15.
# A verdict of PASS with retval=12 proves next is actually emitted and fires correctly.
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M26', $spec) };
    ok(!$@, 'M26 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 3 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M26 verdict is PASS (S==P)');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 12, 'M26 observable-next: generated returns 12 (next skips n==3)');
        my $s_retval = $result->{S}->return_values->[0];
        is($s_retval, 12, 'M26 oracle returns 12 (sanity check)');
    }
}

# Observable-last: foreach 1..5, stop at n==3, accumulate sum.
# Correct sum (last fires)   = 1+2 = 3.
# Miscompile sum (last dropped) = 1+2+3+4+5 = 15.
# A verdict of PASS with retval=3 proves last is actually emitted and fires correctly.
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M27', $spec) };
    ok(!$@, 'M27 run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 3 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M27 verdict is PASS (S==P)');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 3, 'M27 observable-last: generated returns 3 (last stops at n==3)');
        my $s_retval = $result->{S}->return_values->[0];
        is($s_retval, 3, 'M27 oracle returns 3 (sanity check)');
    }
}

done_testing();
