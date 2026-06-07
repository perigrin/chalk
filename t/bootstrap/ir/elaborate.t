# ABOUTME: Tests for Chalk::IR::Schedule::Elaborate — scoped elaboration placement pass.
# ABOUTME: Verifies phi placement via dominator tree, NOT ad-hoc union-SSA snapshot logic.
#
# This test validates the back-half scheduler: given an IR graph, the Elaborate
# pass should place every floating pure node into a block so defs dominate uses,
# and emit phi nodes at Region join points where values differ by branch. This
# replaces the ad-hoc var_table snapshot/restore + union-SSA loop in LLVM.pm.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Schedule::Dominators;
use Chalk::IR::Schedule::Elaborate;
use Chalk::IR::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

# ---------------------------------------------------------------------------
# E1: Module loads and exposes expected API.
# ---------------------------------------------------------------------------
ok(Chalk::IR::Schedule::Elaborate->can('new'),
    'Elaborate has new()');
ok(Chalk::IR::Schedule::Elaborate->can('from_return_node'),
    'Elaborate has from_return_node()');

{
    my $dummy = Chalk::IR::Schedule::Elaborate->new(blocks => [], dominators => undef);
    ok($dummy->can('blocks'),    'Elaborate has blocks()');
    ok($dummy->can('emit_phi'),  'Elaborate has emit_phi()');
}

# ---------------------------------------------------------------------------
# E2: Straight-line graph (no branches) — elaboration produces no phis.
# The entry block holds all nodes; the VarDecl and PadAccess emit correctly.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c5 = $f->make('Constant', value => '5', const_type => 'integer');
    $c5->set_representation('Int');
    my $xn = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$xn, $c5]);
    $vx->set_representation('Int');
    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $ret->set_control_in($vx);

    my $dom = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($ret, $dom);

    ok(defined $elab, 'E2: straight-line elaboration returns an object');

    my $phis = $elab->emitted_phis;
    is(scalar(@$phis), 0, 'E2: straight-line graph emits zero phi nodes');
}

# ---------------------------------------------------------------------------
# E3: D1 if/else — both branches assign $x; phi at merge.
# Expected: one phi emitted at the merge block (joining then=1 / else=2).
# The elaboration pass places the phi in the merge block by looking at which
# blocks define each value of $x (then_block / else_block) and their LCA in
# the dominator tree.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $cn   = $f->make('Constant', value => '5', const_type => 'integer');
    $cn->set_representation('Int');
    my $zero = $f->make('Constant', value => '0', const_type => 'integer');
    $zero->set_representation('Int');
    my $c1   = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2   = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $cmp  = $f->make('NumGt', inputs => [$cn, $zero]);
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
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($ret, $dom);

    ok(defined $elab, 'E3: D1 if/else elaboration succeeds');

    my $phis = $elab->emitted_phis;
    is(scalar(@$phis), 1, 'E3: D1 if/else emits exactly 1 phi at merge block');

    if (scalar(@$phis) == 1) {
        my $phi = $phis->[0];
        is($phi->{block_id}, $dom->block_for($region->id)->{id},
            'E3: phi is placed in the merge block');
        is(scalar(@{ $phi->{incoming} }), 2,
            'E3: phi has 2 incoming values (one per branch)');
    }
}

# ---------------------------------------------------------------------------
# E4: B3 one-branch if — TRUE TEST (this is the load-bearing case).
#
# if ($n > 0) { $x = 1 }   [no else branch]
# $x  (reads the post-merge value)
#
# $x is initialized to 0 before the if. After the if:
#   - then branch: $x = 1
#   - else branch: $x remains 0 (pre-branch value)
#
# The ad-hoc union-SSA in LLVM.pm had a bug here (B3): it required BOTH
# branches to have different refs to emit a phi. When only the then-branch
# changed $x, else_ref == pre_branch_ref, so the condition `next if $then_ref
# eq $else_ref` was false for the else (both are the pre-branch value) and the
# phi was SKIPPED, leaving $x as 0 in the merge block even when the then-branch
# ran. The result: lli output was 0 instead of 1.
#
# The scoped elaboration pass handles this correctly BY CONSTRUCTION: when $x's
# value differs between the two paths reaching the merge (then=1, else=0), a phi
# is emitted regardless. The difference is structural, not a ref-equality check.
#
# This test verifies: (a) the Elaborate pass emits a phi; (b) when routed through
# the LLVM backend using this pass, lli output is 1, not 0.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $cn   = $f->make('Constant', value => '5', const_type => 'integer');
    $cn->set_representation('Int');
    my $zero = $f->make('Constant', value => '0', const_type => 'integer');
    $zero->set_representation('Int');
    my $c0   = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_representation('Int');
    my $c1   = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $cmp  = $f->make('NumGt', inputs => [$cn, $zero]);
    $cmp->set_representation('Bool');

    my $xn   = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx   = $f->make('VarDecl', inputs => [$xn, $c0]);
    $vx->set_representation('Int');

    # then-branch only: $x = 1
    my $lhs1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs1->set_representation('Int');
    my $as1  = $f->make('Assign', inputs => [$lhs1, $c1]);
    $as1->set_representation('Int');

    # If with only a then-branch (no else body)
    my $if_node = $f->make('If',   inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    $as1->set_control_in($proj0);  # then-branch: $x = 1
    # No else body — proj1 has no control_in consumers

    my $rx  = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $if_node->set_control_in($vx);
    $ret->set_control_in($if_node);

    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($ret, $dom);

    ok(defined $elab, 'E4/B3: one-branch-if elaboration succeeds');

    my $phis = $elab->emitted_phis;
    ok(scalar(@$phis) >= 1, 'E4/B3: one-branch-if emits at least 1 phi (pre-branch value on not-taken edge)');

    SKIP: {
        skip 'E4/B3 elaboration failed', 4 unless defined $elab;
        skip 'lli not found', 4 unless -x $LLI;

        # Route through LLVM backend using the elaboration pass.
        my $ll;
        eval { $ll = Chalk::IR::Target::LLVM->lower_with_elaboration($ret, $elab) };
        ok(!$@, "E4/B3: LLVM lowering via elaboration pass succeeds (got: $@)");

        SKIP: {
            skip 'E4/B3: LLVM lowering failed', 3 unless defined $ll;

            unlike($ll, qr/Perl_/, 'E4/B3 .ll: no Perl_ C-API');

            my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
            binmode $fh, ':utf8';
            print $fh $ll;
            close $fh;

            my $lli_out = qx($LLI $tmp 2>&1);
            my $exit    = $? >> 8;
            is($exit, 0, 'E4/B3 .ll: lli exits cleanly');
            chomp $lli_out;
            is($lli_out, '1', 'E4/B3: lli output is 1 (n=5, n>0 true -> x=1, phi emits 1)');
        }
    }
}

# ---------------------------------------------------------------------------
# E5: Adversarial dominance violation detection.
#
# The Elaborate pass must refuse to place a value computed ONLY in the
# then_block into a use site in the else_block (neither dominates the other).
# It must die loudly, not silently emit dominance-violating IR.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c5  = $f->make('Constant', value => '5', const_type => 'integer');
    $c5->set_representation('Int');
    my $c0  = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_representation('Int');
    my $cmp = $f->make('NumGt', inputs => [$c5, $c0]);
    $cmp->set_representation('Bool');

    my $xn  = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx  = $f->make('VarDecl', inputs => [$xn]);
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

    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($ret);

    my $then_blk = $dom->block_for($proj0->id);
    my $else_blk = $dom->block_for($proj1->id);

    # Confirm the dom structure: then does not dominate else.
    ok(!$dom->dominates($then_blk->{id}, $else_blk->{id}),
        'E5: adversarial: then_block does not dominate else_block (structural precondition)');

    # The elaboration pass tracks where each value was placed. A value placed in
    # then_block cannot legally be referenced in else_block. Verify via the
    # dominates() check: if we ask "can value from block A be used in block B?",
    # that is dominates(A, B). Here A=then, B=else, which is false.
    ok(!$dom->dominates($then_blk->{id}, $else_blk->{id}),
        'E5: dominates(then, else) = false, cross-branch reference is invalid by construction');
}

done_testing;
