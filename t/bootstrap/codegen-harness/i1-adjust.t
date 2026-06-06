# ABOUTME: TDD rig test for I1 (ADJUST block emission) — asserts ADJUST side-effect is observable.
# ABOUTME: I1: class C { field $x :param; ADJUST { $x = $x + 1; } method m() { return $x; } }
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness;

# I1 spec: construct C with x => 5 (the :param field), then call method m().
# The ADJUST block runs at construction and increments $x to 6.
# m() returns $x, which must be 6 (proving ADJUST ran), NOT 5 (proving it wasn't skipped).
my $spec = {
    class       => 'C',
    constructor => { params => { x => 5 } },
    method      => 'm',
    method_args => [],
    context     => 'scalar',
};

# --- I1: ADJUST block ---
# class C { field $x :param; ADJUST { $x = $x + 1; } method m() { return $x; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('I1', $spec) };
    ok(!$@, 'I1: run_entry does not die') or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 3 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'I1: verdict is PASS');
        my $retval = $result->{P}->return_values->[0];
        is($retval, 6, 'I1: generated code returns 6 (ADJUST ran and incremented $x from 5 to 6)');
        isnt($retval, 5, 'I1: return value is NOT 5 (confirms ADJUST actually ran, not skipped)');
    }
}

done_testing();
