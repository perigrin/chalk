# ABOUTME: Phase 1a Batch 3 — TDD rig tests for B1-B8 (bare side-effect builtin calls).
# ABOUTME: B4 expects an exception (die "boom"). B8 needs warn added to no-parens emitter list.
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

# --- B1: bare push ---
# class C { method m() { my @list = (); push @list, 1; return scalar @list; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('B1', $spec) };
    ok(!$@, "B1: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'B1: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'B1: returns 1 (array length after push)');
    }
}

# --- B2: bare print ---
# class C { method m() { print "hi"; return 1; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('B2', $spec) };
    ok(!$@, "B2: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'B2: verdict is PASS');
        is($result->{S}->stdout, 'hi', 'B2: oracle stdout is "hi"');
    }
}

# --- B3: bare say ---
# class C { method m() { say "hi"; return 1; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('B3', $spec) };
    ok(!$@, "B3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'B3: verdict is PASS');
        is($result->{S}->stdout, "hi\n", 'B3: oracle stdout is "hi\n"');
    }
}

# --- B4: bare die ---
# class C { method m() { die "boom"; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('B4', $spec) };
    ok(!$@, "B4: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'B4: verdict is PASS');
        ok(defined $result->{P}->exception, 'B4: generated code raises an exception');
    }
}

# --- B5: bare function call no return ---
# class C { method m() { foo(1, 2); return 1; } }
# foo is not defined: both oracle and generated die with "Undefined subroutine"
# before reaching return 1. The harness catches the exception; PASS because
# oracle and generated get the same exception (no return value in either case).
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('B5', $spec) };
    ok(!$@, "B5: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'B5: verdict is PASS');
        ok(defined $result->{P}->exception, 'B5: both oracle and generated raise undefined-sub exception');
    }
}

# --- B6: bare method call no return ---
# class C { method m() { $self->bar(); return 1; } }
# bar is not defined on C: both oracle and generated die with "Can't locate
# object method" before reaching return 1. PASS because exceptions match.
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('B6', $spec) };
    ok(!$@, "B6: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'B6: verdict is PASS');
        ok(defined $result->{P}->exception, 'B6: both oracle and generated raise undefined-method exception');
    }
}

# --- B7: bare unshift ---
# class C { method m() { my @list = (); unshift @list, 1; return scalar @list; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('B7', $spec) };
    ok(!$@, "B7: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'B7: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'B7: returns 1');
    }
}

# --- B8: bare warn ---
# class C { method m() { warn "hi"; return 1; } }
{
    my $result = eval { Chalk::CodeGen::Harness->run_entry('B8', $spec) };
    ok(!$@, "B8: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'B8: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'B8: returns 1');
    }
}

done_testing();
