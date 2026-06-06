# ABOUTME: Phase 1a Batch 7 — TDD rig for I3, M3-M4, M8-M15, M22-M24.
# ABOUTME: I2, M1, M2 are skipped — non-class snippets need a different exercise rig.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness;

# --- I3: my sub ---
# class C { method m() { my sub helper ($n) { return $n * 2; } return helper(3); } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('I3', $spec) };
    ok(!$@, "I3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'I3: verdict is PASS');
        is($result->{P}->return_values->[0], 6, 'I3: returns 6 (3*2)');
    }
}

# --- M3: string interpolation ---
# class C { method m($name) { return "hello $name"; } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => ['world'], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M3', $spec) };
    ok(!$@, "M3: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M3: verdict is PASS');
        is($result->{P}->return_values->[0], 'hello world', 'M3: returns hello world');
    }
}

# --- M4: string interpolation with array ---
# class C { method m() { my @list = (1, 2); return "got @list"; } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M4', $spec) };
    ok(!$@, "M4: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M4: verdict is PASS');
        is($result->{P}->return_values->[0], 'got 1 2', 'M4: returns "got 1 2"');
    }
}

# --- M8: arrow subscript array ($r->[0]) ---
# class C { method m($r) { return $r->[0]; } }
# Pass a real arrayref [42] so the deref executes and returns 42.
# PASS must be on the return-value axis (no exception).
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [[42]], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M8', $spec) };
    ok(!$@, "M8: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 3 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M8: verdict is PASS');
        is($result->{P}->return_values->[0], 42, 'M8: returns 42 (deref path, not exception)');
        ok(!defined $result->{P}->exception, 'M8: no exception — passed via value axis');
    }
}

# --- M9: arrow subscript hash ($r->{key}) ---
# class C { method m($r) { return $r->{key}; } }
# Pass a real hashref {key=>7} so the deref executes and returns 7.
# PASS must be on the return-value axis (no exception).
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [{ key => 7 }], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M9', $spec) };
    ok(!$@, "M9: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 3 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M9: verdict is PASS');
        is($result->{P}->return_values->[0], 7, 'M9: returns 7 (deref path, not exception)');
        ok(!defined $result->{P}->exception, 'M9: no exception — passed via value axis');
    }
}

# --- M10: ref of array ---
# class C { method m() { my @list = (1, 2); my $r = \@list; return $r->[0]; } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M10', $spec) };
    ok(!$@, "M10: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M10: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'M10: returns 1');
    }
}

# --- M11: ref of hash ---
# class C { method m() { my %h = (k => 1); my $r = \%h; return $r->{k}; } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M11', $spec) };
    ok(!$@, "M11: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M11: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'M11: returns 1');
    }
}

# --- M12: static method call ---
# class C { method m() { return Foo::Bar->new(); } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M12', $spec) };
    ok(!$@, "M12: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M12: verdict is PASS');
        ok(defined $result->{P}->exception, 'M12: both raise "Can\'t locate" exception');
    }
}

# --- M13: qualified function call ---
# class C { method m() { return Foo::Bar::baz(1); } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M13', $spec) };
    ok(!$@, "M13: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M13: verdict is PASS');
        ok(defined $result->{P}->exception, 'M13: both raise undefined-sub exception');
    }
}

# --- M14: string concatenation ---
# class C { method m($a) { return "got " . $a; } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => ['it'], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M14', $spec) };
    ok(!$@, "M14: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M14: verdict is PASS');
        is($result->{P}->return_values->[0], 'got it', 'M14: returns "got it"');
    }
}

# --- M15: defined-or assign ---
# class C { method m($x) { my $y; $y //= $x; return $y; } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [5], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M15', $spec) };
    ok(!$@, "M15: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M15: verdict is PASS');
        is($result->{P}->return_values->[0], 5, 'M15: returns 5');
    }
}

# --- M22: sort with block ---
# class C { method m() { my @r = sort { $a <=> $b } (3, 1, 2); return $r[0]; } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M22', $spec) };
    ok(!$@, "M22: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M22: verdict is PASS');
        is($result->{P}->return_values->[0], 1, 'M22: returns 1 (smallest after sort)');
    }
}

# --- M23: bare delete ---
# class C { method m() { my %h = (a => 1); delete $h{a}; return scalar keys %h; } }
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm', method_args => [], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M23', $spec) };
    ok(!$@, "M23: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 2 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M23: verdict is PASS');
        is($result->{P}->return_values->[0], 0, 'M23: returns 0 (empty hash after delete)');
    }
}

# --- M24: chained arrow subscript ---
# class C { method m($r) { return $r->{a}->[0]; } }
# Pass a real nested ref {a=>[9]} so the chained deref executes and returns 9.
# PASS must be on the return-value axis (no exception).
{
    my $spec = { class => 'C', constructor => { params => {} }, method => 'm',
                 method_args => [{ a => [9] }], context => 'scalar' };
    my $result = eval { Chalk::CodeGen::Harness->run_entry('M24', $spec) };
    ok(!$@, "M24: run_entry does not die") or diag("Error: $@");
    SKIP: {
        skip 'run_entry died', 3 if $@;
        my $verdict = $result->{verdict}{verdict} // $result->{verdict};
        is($verdict, 'PASS', 'M24: verdict is PASS');
        is($result->{P}->return_values->[0], 9, 'M24: returns 9 (chained deref path, not exception)');
        ok(!defined $result->{P}->exception, 'M24: no exception — passed via value axis');
    }
}

done_testing();
