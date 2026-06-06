# ABOUTME: Positive tests for Chalk::CodeGen::Harness::HandGraphs — hand-authored MOP/Program graphs.
# ABOUTME: Asserts graph_for("A1") etc. return a Chalk::MOP built directly, not via JSON.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib', 't/lib';

use Chalk::MOP;
use Chalk::CodeGen::Harness::HandGraphs;

# --- T1: graph_for returns a Chalk::MOP, not a loose graph ---

{
    my $result = Chalk::CodeGen::Harness::HandGraphs->graph_for('A1');
    ok(defined $result, 'graph_for("A1") returns a defined value');
    isa_ok($result, 'Chalk::MOP', 'graph_for("A1") returns a Chalk::MOP');
}

# --- T2: graph_for("A4") — VarDecl no initializer ---

{
    my $result = Chalk::CodeGen::Harness::HandGraphs->graph_for('A4');
    ok(defined $result, 'graph_for("A4") returns a defined value');
    isa_ok($result, 'Chalk::MOP', 'graph_for("A4") returns a Chalk::MOP');
}

# --- T3: graph_for("A5") — VarDecl field access ---

{
    my $result = Chalk::CodeGen::Harness::HandGraphs->graph_for('A5');
    ok(defined $result, 'graph_for("A5") returns a defined value');
    isa_ok($result, 'Chalk::MOP', 'graph_for("A5") returns a Chalk::MOP');
}

# --- T4: graph_for("E1") — implicit return ---

{
    my $result = Chalk::CodeGen::Harness::HandGraphs->graph_for('E1');
    ok(defined $result, 'graph_for("E1") returns a defined value');
    isa_ok($result, 'Chalk::MOP', 'graph_for("E1") returns a Chalk::MOP');
}

# --- T5: graph_for("F3") — function call with capture ---

{
    my $result = Chalk::CodeGen::Harness::HandGraphs->graph_for('F3');
    ok(defined $result, 'graph_for("F3") returns a defined value');
    isa_ok($result, 'Chalk::MOP', 'graph_for("F3") returns a Chalk::MOP');
}

# --- T6: Each MOP has at least one non-main class with a method ---

for my $tag (qw(A1 A4 E1)) {
    my $mop  = Chalk::CodeGen::Harness::HandGraphs->graph_for($tag);
    my @classes = grep { $_->name ne 'main' } $mop->classes;
    ok(scalar @classes >= 1, "$tag: MOP has at least one non-main class");
    my @methods = $classes[0]->methods;
    ok(scalar @methods >= 1, "$tag: class has at least one method");
}

# --- T7: A5 MOP has at least one non-main class with a field ---

{
    my $mop = Chalk::CodeGen::Harness::HandGraphs->graph_for('A5');
    my ($cls) = grep { $_->name ne 'main' } $mop->classes;
    ok(defined $cls, 'A5: MOP has a non-main class');
    my @fields = $cls->fields;
    ok(scalar @fields >= 1, 'A5: class has at least one field');
}

# --- T8: unknown tag returns undef ---

{
    my $result = Chalk::CodeGen::Harness::HandGraphs->graph_for('NOSUCHIDIOM');
    ok(!defined $result, 'unknown tag returns undef');
}

done_testing();
