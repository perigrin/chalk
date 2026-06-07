# ABOUTME: TDD tests for the constructive ir-block graph builder (build_graph_from_ir).
# ABOUTME: Proves that named-SSA ir blocks build real SoN graphs without external graph_for builders.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::Graph::TypedInvariant;
use Chalk::CodeGen::Harness::MdtestCorpus;
use Chalk::CodeGen::Harness::LLVMDriver;

my $LLI = '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# ---------------------------------------------------------------------------
# Unit tests for build_graph_from_ir
# ---------------------------------------------------------------------------

# Test 1: arith-add block builds a real graph (no external builder)
{
    my $ir_block = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
END_IR

    my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_block);
    ok(defined $return_node, 'arith-add block returns a defined Return node');
    isa_ok($return_node, 'Chalk::IR::Node::Return',
        'arith-add block returns a Return node');

    # The input to Return is the Add node
    my $inputs = $return_node->inputs;
    ok(defined $inputs && scalar(@$inputs) > 0, 'Return has inputs');
    my $val = $inputs->[0];
    isa_ok($val, 'Chalk::IR::Node::Add', 'Return input is an Add node');
    is($val->representation, 'Int', 'Add node has Int representation');

    # Add's inputs are Int constants
    my $add_inputs = $val->inputs;
    is($add_inputs->[0]->value, '1', 'first constant is 1');
    is($add_inputs->[1]->value, '2', 'second constant is 2');
    is($add_inputs->[0]->representation, 'Int', 'constant 1 has Int repr');
    is($add_inputs->[1]->representation, 'Int', 'constant 2 has Int repr');
}

# Test 2: arith-div block builds a graph with Coerce nodes
{
    my $ir_block = <<'END_IR';
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%d3  = Coerce(%c3 : Int -> Num) :Num
%d4  = Coerce(%c4 : Int -> Num) :Num
%div = Divide(%d3, %d4) :Num
return %div
L: GREEN
END_IR

    my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_block);
    ok(defined $return_node, 'arith-div block returns a defined Return node');

    my $div = $return_node->inputs->[0];
    isa_ok($div, 'Chalk::IR::Node::Divide', 'Return input is a Divide node');
    is($div->representation, 'Num', 'Divide node has Num representation');

    my $div_inputs = $div->inputs;
    isa_ok($div_inputs->[0], 'Chalk::IR::Node::Coerce', 'first Divide input is Coerce');
    isa_ok($div_inputs->[1], 'Chalk::IR::Node::Coerce', 'second Divide input is Coerce');
    is($div_inputs->[0]->from_repr, 'Int', 'first Coerce from Int');
    is($div_inputs->[0]->to_repr,   'Num', 'first Coerce to Num');
    is($div_inputs->[0]->representation, 'Num', 'first Coerce has Num repr');
}

# Test 3: pure-GAP block (only L: GAP line) returns undef
{
    my $ir_block = <<'END_IR';
L: GAP(&& returns an operand not a bool; needs If+Phi short-circuit)
END_IR

    my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_block);
    ok(!defined $return_node, 'pure-GAP block returns undef');
}

# Test 4: arith-add graph passes the TypedInvariant
{
    my $ir_block = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
END_IR

    my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_block);
    my $val   = $return_node->inputs->[0];
    my @nodes = ($return_node->inputs->[0],
                 $return_node->inputs->[0]->inputs->@*);
    my $inv = Chalk::IR::Graph::TypedInvariant->check(\@nodes);
    ok($inv->{ok}, 'arith-add built graph passes TypedInvariant');
    is(scalar(@{ $inv->{violations} }), 0, 'no violations');
}

# Test 5: arith-add graph lowers via LLVMDriver and produces 3
{
    my $ir_block = <<'END_IR';
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
END_IR

    my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_block);
    my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);

    ok(!$meta->{marked_unsupported}, 'arith-add (built from block) is not marked_unsupported');
    my $lli_out = $L->return_values->[0] // '';
    is($lli_out, '3', 'arith-add built-from-block -> lli -> 3 (matches perl)');
}

# Test 6: arith-div graph (built from block) lowers via lli and produces 0.75
{
    my $ir_block = <<'END_IR';
%c3  = Constant(3) :Int
%c4  = Constant(4) :Int
%d3  = Coerce(%c3 : Int -> Num) :Num
%d4  = Coerce(%c4 : Int -> Num) :Num
%div = Divide(%d3, %d4) :Num
return %div
L: GREEN
END_IR

    my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_block);
    my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);

    ok(!$meta->{marked_unsupported}, 'arith-div (built from block) is not marked_unsupported');
    my $lli_out = $L->return_values->[0] // '';
    ok(abs($lli_out - 0.75) < 1e-9, "arith-div built-from-block -> lli -> 0.75 (got '$lli_out')");
}

# Test 7: ill-typed block (Int Add fed with Num without Coerce) fails TypedInvariant
# The builder constructs the graph; the invariant check must catch the type mismatch.
{
    my $ir_block = <<'END_IR';
%c1  = Constant(1) :Num
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
END_IR

    my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_block);
    ok(defined $return_node, 'ill-typed block still builds a graph');

    # But the TypedInvariant must flag violations
    my @nodes = ($return_node->inputs->[0],
                 $return_node->inputs->[0]->inputs->@*);
    my $inv = Chalk::IR::Graph::TypedInvariant->check(\@nodes);
    ok(!$inv->{ok}, 'ill-typed block fails TypedInvariant (Num input to Add without Coerce)');
    ok(scalar(@{ $inv->{violations} }) > 0, 'TypedInvariant records violations');
}

# Test 8: declared L: verdict is parsed from the block
{
    my $green_block = "Constant(1) :Int\nreturn %c1\nL: GREEN\n";
    my $gap_block   = "L: GAP(stale-read: needs program-point reads)\n";

    my $green_verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($green_block);
    my $gap_verdict   = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($gap_block);

    is($green_verdict, 'GREEN', 'GREEN verdict parsed from ir block');
    is($gap_verdict,   'GAP',   'GAP verdict parsed from ir block');
}

done_testing;
