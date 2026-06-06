# ABOUTME: TDD spike test for M19 — list/tuple multi-assignment my ($a,$b)=(1,2).
# ABOUTME: RED->GREEN: no hand graph yet (NOT-YET-COVERED); implements ListAssign to reach PASS.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness;
use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::CodeGen::Harness::PerlDriver;
use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::Add;

my $spec = {
    class       => 'C',
    constructor => { params => {} },
    method      => 'm',
    method_args => [],
    context     => 'scalar',
};

# --- T1: M19 graph_for returns defined value (hand graph exists) ---
# RED state: HandGraphs does not yet have a builder for M19 — this test fails.
# GREEN state: after implementing ListAssign + hand graph, graph_for returns a MOP.
{
    my $result = Chalk::CodeGen::Harness::HandGraphs->graph_for('M19');
    ok(defined $result,
        'M19: hand graph is defined (graph_for returns a Chalk::MOP)');
}

# --- T2: run_entry('M19') returns PASS with return value 3 ---
# GREEN state: after implementing ListAssign + hand graph, this must pass.
# M19 = class C { method m() { my ($a, $b) = (1, 2); return $a + $b; } }
# $a=1, $b=2, return $a+$b = 3.
{
    my $graph = Chalk::CodeGen::Harness::HandGraphs->graph_for('M19');
    SKIP: {
        skip 'M19 hand graph not yet defined (RED state)', 2 unless defined $graph;

        my $result = eval { Chalk::CodeGen::Harness->run_entry('M19', $spec) };
        if ($@) {
            fail("M19: run_entry died: $@");
            fail('M19: generated code returns 3');
        } else {
            my $verdict = ref($result->{verdict}) eq 'HASH'
                ? $result->{verdict}{verdict}
                : $result->{verdict};
            is($verdict, 'PASS', 'M19: verdict is PASS');

            SKIP: {
                skip 'verdict is not PASS', 1 unless ($verdict // '') eq 'PASS';
                my $retval = $result->{P}->return_values->[0];
                is($retval, 3, 'M19: generated code returns 3 ($a+$b where $a=1, $b=2)');
            }
        }
    }
}

# --- T3: negative — arrayref miscompile guard ---
# If a naive graph emits `my ($a,$b) = [1,2]` (arrayref), $a gets the
# arrayref and $b gets undef, so $a+$b would not be 3.  This test
# constructs that naive wrong graph and confirms the rig returns a
# non-3 value (a memory address), i.e. it is NOT PASS.
# This confirms the miscompile guard is in place: even before the fix,
# the oracle returns 3 but the naive graph does not.
{
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Wrong: my $a = [1, 2] — $a gets the arrayref, not 1
    my $e1  = $factory->make('Constant', value => '1', const_type => 'integer');
    my $e2  = $factory->make('Constant', value => '2', const_type => 'integer');
    my $arr = $factory->make('ArrayRef', inputs => [[$e1, $e2]]);

    # my $a = [1, 2]
    my $name_a = $factory->make('Constant', value => '$a', const_type => 'string');
    my $var_a  = $factory->make('VarDecl', inputs => [$name_a, $arr], scope => 'my');
    $var_a->set_control_in($start);

    # my $b — uninitialized
    my $name_b = $factory->make('Constant', value => '$b', const_type => 'string');
    my $var_b  = $factory->make('VarDecl', inputs => [$name_b, undef], scope => 'my');
    $var_b->set_control_in($var_a);

    # return $a + $b
    my $op_plus = $factory->make('Constant', value => '+', const_type => 'string');
    my $a_read  = $factory->make('Constant', value => '$a', const_type => 'variable');
    my $b_read  = $factory->make('Constant', value => '$b', const_type => 'variable');
    my $sum     = $factory->make('Add', inputs => [$op_plus, $a_read, $b_read]);
    my $ret     = $factory->make_cfg('Return', inputs => [$sum]);
    $ret->set_control_in($var_b);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $e1, $e2, $arr, $name_a, $var_a, $name_b, $var_b,
               $op_plus, $a_read, $b_read, $sum, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);

    my ($P_wrong, undef) = eval {
        Chalk::CodeGen::Harness::PerlDriver->run($mop, $spec)
    };
    if ($@) {
        pass('T3: naive arrayref graph: rig died (confirms it is not PASS)');
    } else {
        my $retval = $P_wrong->return_values->[0] // 'undef';
        isnt($retval, 3,
            "T3: naive arrayref miscompile guard — retval '$retval' is not 3 (confirms miscompile)");
        note("T3: naive wrong graph returned: '$retval' (expected NOT 3 — miscompile detected)");
    }
}

done_testing();
