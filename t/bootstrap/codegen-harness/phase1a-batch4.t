# ABOUTME: Phase 1a Batch 4 — TDD rig tests for F1-F2 (method call/chain) and G1-G4 (deref/subscript).
# ABOUTME: F1/F2 use undefined methods so behavior match via matching exceptions.
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

# --- F1: method call chain ---
# class C { method m() { return $self->foo->bar; } }
# foo/bar not defined: both oracle and generated raise "Can't locate object method"
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('F1', $spec) };
    ok(!$@, "F1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'F1: verdict is PASS');
        ok(defined $result->{P}->exception, 'F1: both oracle and generated raise exception');
    }
}

# --- F2: method call with args ---
# class C { method m() { return $self->foo(1, 2, 3); } }
# foo not defined: both oracle and generated raise exception
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('F2', $spec) };
    ok(!$@, "F2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'F2: verdict is PASS');
        ok(defined $result->{P}->exception, 'F2: both oracle and generated raise exception');
    }
}

# --- G1: postfix deref array ---
# class C { method m() { my $r = [1, 2]; return $r->@*; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('G1', $spec) };
    ok(!$@, "G1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'G1: verdict is PASS');
    }
}

# --- G2: postfix deref hash ---
# class C { method m() { my $r = { a => 1 }; return $r->%*; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('G2', $spec) };
    ok(!$@, "G2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'G2: verdict is PASS');
    }
}

# --- G3: subscript array ---
# class C { method m() { my @a = (1, 2); return $a[0]; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('G3', $spec) };
    ok(!$@, "G3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'G3: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'G3: returns 1');
    }
}

# --- G4: subscript hash ---
# class C { method m() { my %h = (k => 1); return $h{k}; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('G4', $spec) };
    ok(!$@, "G4: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'G4: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'G4: returns 1');
    }
}

done_testing();
