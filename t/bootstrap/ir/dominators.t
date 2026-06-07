# ABOUTME: Tests for Chalk::IR::Schedule::Dominators — CFG skeleton + dominator tree.
# ABOUTME: Verifies idom() and dominates() for D1 (if/else), D2 (while), D7 (nested if).
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Schedule::Dominators;

my $LLI = '/usr/lib/llvm-15/bin/lli';

# ---------------------------------------------------------------------------
# T1: Module loads and exposes the expected API.
# ---------------------------------------------------------------------------
ok(Chalk::IR::Schedule::Dominators->can('new'),
    'Dominators has new()');
ok(Chalk::IR::Schedule::Dominators->can('from_return_node'),
    'Dominators has from_return_node()');

{
    # Instantiate a dummy object to check instance methods exist
    my $d = Chalk::IR::Schedule::Dominators->new(blocks => [], idoms => {});
    ok($d->can('idom'),       'Dominators has idom()');
    ok($d->can('dominates'),  'Dominators has dominates()');
    ok($d->can('blocks'),     'Dominators has blocks()');
}

# ---------------------------------------------------------------------------
# Helper: build a simple straight-line graph (no branches) for a baseline.
# Entry -> VarDecl -> Return
# DOM: entry doms all; VarDecl doms Return.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $xn = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$xn, $c1]);
    $vx->set_representation('Int');
    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $ret->set_control_in($vx);

    my $dom = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    ok(defined $dom, 'T0: straight-line graph builds a Dominators object');

    my $blocks = $dom->blocks;
    ok(scalar(@$blocks) >= 1, 'T0: straight-line graph has at least 1 block');

    # The entry block must exist
    my ($entry_block) = grep { $_->{id} eq 'entry' } @$blocks;
    ok(defined $entry_block, 'T0: entry block exists');
}

# ---------------------------------------------------------------------------
# D1: if/else graph
#
# CFG skeleton:
#   entry -> If -> Proj0(then_block) -> Region(merge_block) -> (exit)
#                -> Proj1(else_block) -> Region(merge_block)
#
# Expected dominator tree:
#   entry idoms if_block
#   if_block idoms then_block, else_block, merge_block
#   (then_block and else_block each dom only themselves)
#   merge_block idoms nothing further here (the exit is implicit)
#
# dominates(entry, X) = true for all X
# dominates(if_block, then_block) = true
# dominates(if_block, else_block) = true
# dominates(if_block, merge_block) = true
# dominates(then_block, else_block) = false (siblings)
# dominates(else_block, then_block) = false (siblings)
# dominates(merge_block, if_block) = false (forward in CFG only)
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c5   = $f->make('Constant', value => '5', const_type => 'integer');
    $c5->set_representation('Int');
    my $c0   = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_representation('Int');
    my $c1   = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2   = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $cmp  = $f->make('NumGt', inputs => [$c5, $c0]);
    $cmp->set_representation('Bool');

    my $xn   = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx   = $f->make('VarDecl', inputs => [$xn]);
    $vx->set_representation('Int');

    my $lhs1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs1->set_representation('Int');
    my $as1  = $f->make('Assign', inputs => [$lhs1, $c1]);
    $as1->set_representation('Int');

    my $lhs2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs2->set_representation('Int');
    my $as2  = $f->make('Assign', inputs => [$lhs2, $c2]);
    $as2->set_representation('Int');

    my $if_node = $f->make('If',   inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    $as1->set_control_in($proj0);
    $as2->set_control_in($proj1);

    my $rx  = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $if_node->set_control_in($vx);
    $ret->set_control_in($if_node);

    my $dom = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    ok(defined $dom, 'D1: builds a Dominators object');

    my $blocks = $dom->blocks;
    # Expect: entry, if-block (one block for pre-if code + the If itself),
    # then_block (Proj0 side), else_block (Proj1 side), merge_block (Region).
    my %by_id = map { $_->{id} => $_ } @$blocks;
    ok(exists $by_id{entry},       'D1: entry block exists');

    # Find the blocks: the Proj0 node defines the then_block, Proj1 the else_block,
    # Region defines the merge_block. The If node lives in the entry block.
    my $then_block  = $dom->block_for($proj0->id);
    my $else_block  = $dom->block_for($proj1->id);
    my $merge_block = $dom->block_for($region->id);
    my $if_block    = $dom->block_for($if_node->id);

    ok(defined $then_block,  'D1: then_block (Proj0 block) exists');
    ok(defined $else_block,  'D1: else_block (Proj1 block) exists');
    ok(defined $merge_block, 'D1: merge_block (Region block) exists');
    ok(defined $if_block,    'D1: if_block (If node block) exists');

    # Dominator assertions
    ok($dom->dominates($if_block->{id}, $then_block->{id}),
        'D1: if_block dominates then_block');
    ok($dom->dominates($if_block->{id}, $else_block->{id}),
        'D1: if_block dominates else_block');
    ok($dom->dominates($if_block->{id}, $merge_block->{id}),
        'D1: if_block dominates merge_block');
    ok(!$dom->dominates($then_block->{id}, $else_block->{id}),
        'D1: then_block does NOT dominate else_block (siblings)');
    ok(!$dom->dominates($else_block->{id}, $then_block->{id}),
        'D1: else_block does NOT dominate then_block (siblings)');
    ok(!$dom->dominates($merge_block->{id}, $if_block->{id}),
        'D1: merge_block does NOT dominate if_block (forward only)');

    # Entry dominates everything
    ok($dom->dominates('entry', $then_block->{id}),
        'D1: entry dominates then_block');
    ok($dom->dominates('entry', $else_block->{id}),
        'D1: entry dominates else_block');
    ok($dom->dominates('entry', $merge_block->{id}),
        'D1: entry dominates merge_block');

    # Every block dominates itself
    for my $b (@$blocks) {
        ok($dom->dominates($b->{id}, $b->{id}),
            "D1: block $b->{id} dominates itself");
    }
}

# ---------------------------------------------------------------------------
# D2: while loop graph
#
# CFG skeleton:
#   entry (preheader) -> Loop header -> Proj0 (body) -> Loop header (back edge)
#                                    -> Proj1 (exit) -> Region (exit) -> (end)
#
# Expected dominator tree (reducible loop):
#   entry idoms loop_header
#   loop_header idoms body_block, exit_block, merge_block
#   body_block does NOT dominate loop_header (back edge, not a tree edge)
#   loop_header dominates itself, body_block, exit_block, merge_block
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c3   = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');
    my $c0a  = $f->make('Constant', value => '0', const_type => 'integer');
    $c0a->set_representation('Int');
    my $c0b  = $f->make('Constant', value => '0', const_type => 'integer');
    $c0b->set_representation('Int');
    my $one  = $f->make('Constant', value => '1', const_type => 'integer');
    $one->set_representation('Int');

    my $nn   = $f->make('Constant', value => '$n', const_type => 'string');
    my $sn   = $f->make('Constant', value => '$s', const_type => 'string');
    my $vn   = $f->make('VarDecl', inputs => [$nn, $c3]);
    $vn->set_representation('Int');
    my $vs   = $f->make('VarDecl', inputs => [$sn, $c0a]);
    $vs->set_representation('Int');

    my $rn0  = $f->make('PadAccess', targ => 0, varname => '$n', inputs => [$vn]);
    $rn0->set_representation('Int');
    my $rs0  = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs0->set_representation('Int');

    my $loop = $f->make('Loop', inputs => [$vs, undef]);

    my $n_phi = $f->make('Phi', region => $loop, values => [$rn0]);
    $n_phi->set_representation('Int');
    my $s_phi = $f->make('Phi', region => $loop, values => [$rs0]);
    $s_phi->set_representation('Int');

    my $cmp  = $f->make('NumGt', inputs => [$n_phi, $c0b]);
    $cmp->set_representation('Bool');
    $cmp->set_control_in($loop);   # structural: header condition

    my $s_new = $f->make('Add', inputs => [$s_phi, $n_phi]);
    $s_new->set_representation('Int');
    my $n_new = $f->make('Subtract', inputs => [$n_phi, $one]);
    $n_new->set_representation('Int');

    $n_phi->set_backedge($n_new);
    $s_phi->set_backedge($s_new);

    my $body_proj = $f->make('Proj', inputs => [$loop], index => 0);
    my $exit_proj = $f->make('Proj', inputs => [$loop], index => 1);
    my $exit_region = $f->make('Region', inputs => [$exit_proj]);
    $loop->set_region($exit_region);

    $n_new->set_control_in($body_proj);
    $s_new->set_control_in($body_proj);

    my $ret = $f->make_cfg('Return', inputs => [$s_phi]);
    $vs->set_control_in($vn);
    $loop->set_control_in($vs);
    $ret->set_control_in($loop);

    my $dom = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    ok(defined $dom, 'D2: builds a Dominators object');

    my $blocks = $dom->blocks;

    my $loop_block  = $dom->block_for($loop->id);
    my $body_block  = $dom->block_for($body_proj->id);
    my $exit_block  = $dom->block_for($exit_proj->id);

    ok(defined $loop_block,  'D2: loop header block exists');
    ok(defined $body_block,  'D2: body block (Proj0) exists');
    ok(defined $exit_block,  'D2: exit block (Proj1) exists');

    ok($dom->dominates($loop_block->{id}, $body_block->{id}),
        'D2: loop_block dominates body_block');
    ok($dom->dominates($loop_block->{id}, $exit_block->{id}),
        'D2: loop_block dominates exit_block');
    ok(!$dom->dominates($body_block->{id}, $loop_block->{id}),
        'D2: body_block does NOT dominate loop_block (back-edge does not flip DOM)');

    ok($dom->dominates('entry', $loop_block->{id}),
        'D2: entry dominates loop_block');

    for my $b (@$blocks) {
        ok($dom->dominates($b->{id}, $b->{id}),
            "D2: block $b->{id} dominates itself");
    }
}

# ---------------------------------------------------------------------------
# D7: nested if graph
#
# CFG:
#   entry -> outer_If -> outer_Proj0 -> inner_If -> inner_Proj0 (then-inner)
#                                                 -> inner_Proj1 (else-inner)
#                                                 -> inner_Region
#                     -> outer_Proj1 (else-outer)
#                     -> outer_Region (merge)
#
# Expected dominator tree:
#   entry doms outer_if_block
#   outer_if_block doms outer_then_block (outer_Proj0), outer_else_block (outer_Proj1),
#                       outer_merge_block (outer_Region)
#   outer_then_block (outer_Proj0) doms inner_if_block, inner_then_block, inner_else_block,
#                                       inner_merge_block
#   inner_if_block doms inner_then_block, inner_else_block, inner_merge_block
#   inner_then_block does NOT dom inner_else_block (siblings)
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $n    = $f->make('Constant', value => '5', const_type => 'integer');
    $n->set_representation('Int');
    my $zero = $f->make('Constant', value => '0', const_type => 'integer');
    $zero->set_representation('Int');
    my $three= $f->make('Constant', value => '3', const_type => 'integer');
    $three->set_representation('Int');
    my $c3v  = $f->make('Constant', value => '3', const_type => 'integer');
    $c3v->set_representation('Int');
    my $c1v  = $f->make('Constant', value => '1', const_type => 'integer');
    $c1v->set_representation('Int');
    my $c0v  = $f->make('Constant', value => '0', const_type => 'integer');
    $c0v->set_representation('Int');

    my $xn   = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx   = $f->make('VarDecl', inputs => [$xn]);
    $vx->set_representation('Int');

    my $cmp_out = $f->make('NumGt', inputs => [$n, $zero]);
    $cmp_out->set_representation('Bool');
    my $cmp_in  = $f->make('NumGt', inputs => [$n, $three]);
    $cmp_in->set_representation('Bool');

    my $lhs3 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs3->set_representation('Int');
    my $as3  = $f->make('Assign', inputs => [$lhs3, $c3v]);
    $as3->set_representation('Int');

    my $lhs1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs1->set_representation('Int');
    my $as1  = $f->make('Assign', inputs => [$lhs1, $c1v]);
    $as1->set_representation('Int');

    my $lhs0 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs0->set_representation('Int');
    my $as0  = $f->make('Assign', inputs => [$lhs0, $c0v]);
    $as0->set_representation('Int');

    my $inner_if = $f->make('If', inputs => [$vx, $cmp_in]);
    my $inner_p0 = $f->make('Proj', inputs => [$inner_if], index => 0);
    my $inner_p1 = $f->make('Proj', inputs => [$inner_if], index => 1);
    my $inner_reg= $f->make('Region', inputs => [$inner_p0, $inner_p1]);
    $inner_if->set_region($inner_reg);

    my $outer_if = $f->make('If', inputs => [$vx, $cmp_out]);
    my $outer_p0 = $f->make('Proj', inputs => [$outer_if], index => 0);
    my $outer_p1 = $f->make('Proj', inputs => [$outer_if], index => 1);
    my $outer_reg= $f->make('Region', inputs => [$outer_p0, $outer_p1]);
    $outer_if->set_region($outer_reg);

    $as3->set_control_in($inner_p0);
    $as1->set_control_in($inner_p1);
    $as0->set_control_in($outer_p1);
    $inner_if->set_control_in($outer_p0);

    my $rx  = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $outer_if->set_control_in($vx);
    $ret->set_control_in($outer_if);

    my $dom = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    ok(defined $dom, 'D7: builds a Dominators object');

    my $outer_then_block = $dom->block_for($outer_p0->id);
    my $outer_else_block = $dom->block_for($outer_p1->id);
    my $inner_then_block = $dom->block_for($inner_p0->id);
    my $inner_else_block = $dom->block_for($inner_p1->id);
    my $outer_if_block   = $dom->block_for($outer_if->id);
    my $inner_if_block   = $dom->block_for($inner_if->id);

    ok(defined $outer_then_block, 'D7: outer_then_block exists');
    ok(defined $outer_else_block, 'D7: outer_else_block exists');
    ok(defined $inner_then_block, 'D7: inner_then_block exists');
    ok(defined $inner_else_block, 'D7: inner_else_block exists');

    ok($dom->dominates($outer_if_block->{id}, $outer_then_block->{id}),
        'D7: outer_if doms outer_then');
    ok($dom->dominates($outer_if_block->{id}, $outer_else_block->{id}),
        'D7: outer_if doms outer_else');
    ok($dom->dominates($outer_then_block->{id}, $inner_if_block->{id}),
        'D7: outer_then doms inner_if (inner if is inside outer then)');
    ok($dom->dominates($outer_then_block->{id}, $inner_then_block->{id}),
        'D7: outer_then doms inner_then');
    ok($dom->dominates($outer_then_block->{id}, $inner_else_block->{id}),
        'D7: outer_then doms inner_else');
    ok($dom->dominates($inner_if_block->{id}, $inner_then_block->{id}),
        'D7: inner_if doms inner_then');
    ok($dom->dominates($inner_if_block->{id}, $inner_else_block->{id}),
        'D7: inner_if doms inner_else');
    ok(!$dom->dominates($inner_then_block->{id}, $inner_else_block->{id}),
        'D7: inner_then does NOT dom inner_else (siblings)');
    ok(!$dom->dominates($inner_else_block->{id}, $inner_then_block->{id}),
        'D7: inner_else does NOT dom inner_then (siblings)');
    ok(!$dom->dominates($outer_else_block->{id}, $inner_if_block->{id}),
        'D7: outer_else does NOT dom inner_if (different branches)');

    ok($dom->dominates('entry', $outer_if_block->{id}),
        'D7: entry doms outer_if_block');

    for my $b ($dom->blocks->@*) {
        ok($dom->dominates($b->{id}, $b->{id}),
            "D7: block $b->{id} dominates itself");
    }
}

# ---------------------------------------------------------------------------
# ADVERSARIAL: a value placed in a non-dominating block must fail loudly.
#
# Build a D1 graph, then verify that if we try to reference a value that
# was defined ONLY in the then_block from the else_block (not dominated),
# the dominators object detects the violation via dominates() returning false.
# This is the structural check the scoped-elaboration pass will enforce.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c5  = $f->make('Constant', value => '5', const_type => 'integer');
    $c5->set_representation('Int');
    my $c0  = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_representation('Int');
    my $cmp = $f->make('NumGt', inputs => [$c5, $c0]);
    $cmp->set_representation('Bool');

    my $xn   = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx   = $f->make('VarDecl', inputs => [$xn]);
    $vx->set_representation('Int');

    my $if_node = $f->make('If', inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $if_node->set_control_in($vx);
    $ret->set_control_in($if_node);

    my $dom = Chalk::IR::Schedule::Dominators->from_return_node($ret);

    my $then_blk = $dom->block_for($proj0->id);
    my $else_blk = $dom->block_for($proj1->id);

    # then_block does not dominate else_block — a value defined only in then
    # CANNOT be validly referenced in else (no dominance). The pass MUST refuse.
    ok(!$dom->dominates($then_blk->{id}, $else_blk->{id}),
        'ADVERSARIAL: then_block does NOT dominate else_block (cross-branch use is invalid)');
    ok(!$dom->dominates($else_blk->{id}, $then_blk->{id}),
        'ADVERSARIAL: else_block does NOT dominate then_block (cross-branch use is invalid)');
}

done_testing;
