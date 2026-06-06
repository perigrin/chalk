# ABOUTME: Batch F CFG harness tests — D8 (try/catch).
# ABOUTME: Exercises both: throw-and-catch path and (structural) no-throw path via oracle match.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness;

# D8: try { die "boom"; } catch ($e) { return 0; } return 1;
# The try body always dies. The catch block returns 0.
# Both oracle and generated code return 0.
# The outer `return 1` is unreachable.
{
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('D8', $spec) };
    ok(!$@, 'D8 run_entry does not die (harness)') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'D8 verdict is PASS (try dies, catch returns 0)');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 0, 'D8 catch path: returns 0 (catch block fires)');
    }
}

done_testing();
