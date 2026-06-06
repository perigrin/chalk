# ABOUTME: Schedule-survival tests for Chalk::CodeGen::Harness::HandGraphs.
# ABOUTME: Asserts each hand graph passes EagerPinning and emits real Perl output.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::Bootstrap::Perl::Target::Perl;
use Chalk::IR::Scheduler::EagerPinning;

# Helper: extract the first method from the first non-main class in a MOP.
sub first_method($mop) {
    my ($cls) = grep { $_->name ne 'main' } $mop->classes;
    return undef unless defined $cls;
    my @methods = $cls->methods;
    return $methods[0];
}

# --- T1: A1 graph survives EagerPinning ---
# A1: class C { method m() { my $x = 1; return $x; } }
# Expected schedule: VarDecl($x=1), Return($x)

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('A1');
    my $method = first_method($mop);
    ok(defined $method, 'A1: MOP has a method to schedule');

    my $sched = eval {
        Chalk::IR::Scheduler::EagerPinning->new->schedule($method);
    };
    ok(!$@, "A1: EagerPinning does not die: $@");
    isa_ok($sched, 'Chalk::IR::Schedule', 'A1: schedule is a Schedule object');

    SKIP: {
        skip 'no schedule', 2 unless defined $sched;
        my @items = $sched->items->@*;
        ok(scalar @items >= 2, 'A1: schedule has at least 2 items (VarDecl + Return)');
        is($items[-1]->node->operation, 'Return', 'A1: last schedule item is Return');
    }
}

# --- T2: A1 MOP feeds Target::Perl->generate and emits real Perl ---

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('A1');
    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $result = eval { $target->generate($mop) };
    ok(!$@, "A1: Target::Perl->generate does not die: $@");
    ok(defined $result, 'A1: generate returns a defined value');

    SKIP: {
        skip 'no result', 3 unless defined $result;
        ok(ref($result) eq 'HASH', 'A1: generate returns a hashref');
        my $code = join("\n", values $result->%*);
        ok($code =~ /my\s+\$x\s*=\s*1/, 'A1: emitted Perl contains "my $x = 1"');
        ok($code =~ /return\s+\$x/, 'A1: emitted Perl contains "return $x"');
    }
}

# --- T3: A4 graph survives EagerPinning ---
# A4: class C { method m() { my $x; $x = 1; return $x; } }

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('A4');
    my $method = first_method($mop);
    ok(defined $method, 'A4: MOP has a method');

    my $sched = eval {
        Chalk::IR::Scheduler::EagerPinning->new->schedule($method);
    };
    ok(!$@, "A4: EagerPinning does not die: $@");
    isa_ok($sched, 'Chalk::IR::Schedule', 'A4: schedule is a Schedule object');

    SKIP: {
        skip 'no schedule', 1 unless defined $sched;
        my @items = $sched->items->@*;
        ok(scalar @items >= 1, 'A4: schedule has at least 1 item');
    }
}

# --- T4: A4 MOP emits Perl with uninitialised var declaration ---

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('A4');
    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $result = eval { $target->generate($mop) };
    ok(!$@, "A4: Target::Perl->generate does not die: $@");

    SKIP: {
        skip 'no result', 1 unless defined $result;
        my $code = join("\n", values $result->%*);
        ok($code =~ /my\s+\$x/, 'A4: emitted Perl contains "my $x"');
    }
}

# --- T5: A5 graph survives EagerPinning ---
# A5: class C { field $x :param; method m() { return $x; } }

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('A5');
    my $method = first_method($mop);
    ok(defined $method, 'A5: MOP has a method');

    my $sched = eval {
        Chalk::IR::Scheduler::EagerPinning->new->schedule($method);
    };
    ok(!$@, "A5: EagerPinning does not die: $@");
    isa_ok($sched, 'Chalk::IR::Schedule', 'A5: schedule is a Schedule object');
}

# --- T6: A5 MOP emits Perl with field and return ---

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('A5');
    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $result = eval { $target->generate($mop) };
    ok(!$@, "A5: Target::Perl->generate does not die: $@");

    SKIP: {
        skip 'no result', 2 unless defined $result;
        my $code = join("\n", values $result->%*);
        ok($code =~ /field\s+\$x\s*:param/, 'A5: emitted Perl contains "field $x :param"');
        ok($code =~ /return\s+\$x/, 'A5: emitted Perl contains "return $x"');
    }
}

# --- T7: E1 graph survives EagerPinning ---
# E1: class C { method m() { my $x = 1; $x } }  — implicit/synthetic return

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('E1');
    my $method = first_method($mop);
    ok(defined $method, 'E1: MOP has a method');

    my $sched = eval {
        Chalk::IR::Scheduler::EagerPinning->new->schedule($method);
    };
    ok(!$@, "E1: EagerPinning does not die: $@");
    isa_ok($sched, 'Chalk::IR::Schedule', 'E1: schedule is a Schedule object');

    SKIP: {
        skip 'no schedule', 1 unless defined $sched;
        my @items = $sched->items->@*;
        ok(scalar @items >= 1, 'E1: schedule has at least 1 item');
    }
}

# --- T8: E1 MOP emits Perl — emitted Perl contains var declaration ---

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('E1');
    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $result = eval { $target->generate($mop) };
    ok(!$@, "E1: Target::Perl->generate does not die: $@");

    SKIP: {
        skip 'no result', 1 unless defined $result;
        my $code = join("\n", values $result->%*);
        ok($code =~ /my\s+\$x\s*=\s*1/, 'E1: emitted Perl contains "my $x = 1"');
    }
}

# --- T9: F3 graph survives EagerPinning ---
# F3: class C { method m() { my $r = foo(1, 2); return $r; } }

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('F3');
    my $method = first_method($mop);
    ok(defined $method, 'F3: MOP has a method');

    my $sched = eval {
        Chalk::IR::Scheduler::EagerPinning->new->schedule($method);
    };
    ok(!$@, "F3: EagerPinning does not die: $@");
    isa_ok($sched, 'Chalk::IR::Schedule', 'F3: schedule is a Schedule object');

    SKIP: {
        skip 'no schedule', 2 unless defined $sched;
        my @items = $sched->items->@*;
        ok(scalar @items >= 2, 'F3: schedule has at least 2 items (VarDecl + Return)');
        is($items[-1]->node->operation, 'Return', 'F3: last schedule item is Return');
    }
}

# --- T10: F3 MOP emits Perl with function call capture ---

{
    my $mop    = Chalk::CodeGen::Harness::HandGraphs->graph_for('F3');
    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $result = eval { $target->generate($mop) };
    ok(!$@, "F3: Target::Perl->generate does not die: $@");

    SKIP: {
        skip 'no result', 2 unless defined $result;
        my $code = join("\n", values $result->%*);
        ok($code =~ /my\s+\$r\s*=\s*foo\s*\(/, 'F3: emitted Perl contains "my $r = foo("');
        ok($code =~ /return\s+\$r/, 'F3: emitted Perl contains "return $r"');
    }
}

done_testing();
