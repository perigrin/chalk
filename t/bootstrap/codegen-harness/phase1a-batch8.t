# ABOUTME: Phase 1a Batch 8 — TDD rig tests for I2, M1, M2 (non-class top-level sub idioms).
# ABOUTME: Uses sub_name spec + capture_sub rig extension to exercise these without class wrapping.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::CodeGen::Harness;

# --- I2: top-level sub ---
# sub greet ($name) { return "hi $name"; }
{
    my $spec = { sub_name => 'greet', sub_args => ['world'], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('I2', $spec) };
    ok(!$@, "I2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'I2: verdict is PASS');
        is($result->{P}->return_values->[0], 'hi world', 'I2: returns "hi world"');
    }
}

# --- M1: use pragma ---
# use strict; use warnings; sub greet { return "hi"; }
{
    my $spec = { sub_name => 'greet', sub_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M1', $spec) };
    ok(!$@, "M1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M1: verdict is PASS');
        is($result->{P}->return_values->[0], 'hi', 'M1: returns "hi"');
    }
}

# --- M2: use module with import ---
# use List::Util qw(first sum); sub greet { return first { $_ > 1 } (0, 2, 3); }
{
    my $spec = { sub_name => 'greet', sub_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M2', $spec) };
    ok(!$@, "M2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M2: verdict is PASS');
        is($result->{P}->return_values->[0], 2, 'M2: returns 2 (first element > 1)');
    }
}

done_testing();
