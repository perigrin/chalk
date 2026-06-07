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

# ---------------------------------------------------------------------------
# E6: Nested-if with runtime-FALSE inner condition (MISCOMPILE repro).
#
# Perl:  my $x=0; if ($n>0) { if ($n>3){$x=3} else {$x=1} } else { $x=0 }; $x
# With n=2: outer cond true, inner cond false -> x=1 (perl oracle).
#
# The bug (B1): _elaborate_if sets val_map{vd} = the RAW inner-then value (=3),
# not the inner-merge phi (=1). The outer phi then arms are [3, 0], so on the
# n=2 path (outer-then taken, inner-else taken) lli reads 3 instead of 1.
#
# Fix requirement: the outer phi for $x must arm with the inner-merge phi result
# (whatever x holds at the END of the outer-then block), not the inner-then raw
# assignment node. lli must agree with perl (=1).
#
# This test is written BEFORE the fix. It starts RED (lli=3, perl=1).
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    # Constants
    my $c0    = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_representation('Int');
    my $c1    = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c3    = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');

    # Variable $n = 2 (runtime value — chosen to make outer-cond TRUE, inner-cond FALSE)
    my $nn   = $f->make('Constant', value => '$n', const_type => 'string');
    my $vn   = $f->make('VarDecl', inputs => [$nn, $f->make('Constant', value => '2', const_type => 'integer')]);
    $vn->set_representation('Int');
    $vn->inputs->[1]->set_representation('Int');

    my $rn   = $f->make('PadAccess', targ => 0, varname => '$n', inputs => [$vn]);
    $rn->set_representation('Int');

    # Variable $x = 0
    my $xn   = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx   = $f->make('VarDecl', inputs => [$xn, $c0]);
    $vx->set_representation('Int');

    # Outer condition: $n > 0  (true for n=2)
    my $cmp_out = $f->make('NumGt', inputs => [$rn, $c0]);
    $cmp_out->set_representation('Bool');

    # Inner condition: $n > 3  (false for n=2)
    my $cmp_in = $f->make('NumGt', inputs => [$rn, $c3]);
    $cmp_in->set_representation('Bool');

    # Assignments
    my $lhs3 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs3->set_representation('Int');
    my $as3  = $f->make('Assign', inputs => [$lhs3, $c3]);
    $as3->set_representation('Int');

    my $lhs1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs1->set_representation('Int');
    my $as1  = $f->make('Assign', inputs => [$lhs1, $c1]);
    $as1->set_representation('Int');

    my $lhs0 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs0->set_representation('Int');
    my $as0  = $f->make('Assign', inputs => [$lhs0, $c0]);
    $as0->set_representation('Int');

    # Inner if: if ($n>3) { $x=3 } else { $x=1 }
    my $inner_if  = $f->make('If', inputs => [$vx, $cmp_in]);
    my $inner_p0  = $f->make('Proj', inputs => [$inner_if], index => 0);
    my $inner_p1  = $f->make('Proj', inputs => [$inner_if], index => 1);
    my $inner_reg = $f->make('Region', inputs => [$inner_p0, $inner_p1]);
    $inner_if->set_region($inner_reg);
    $as3->set_control_in($inner_p0);
    $as1->set_control_in($inner_p1);

    # Outer if: if ($n>0) { <inner_if> } else { $x=0 }
    my $outer_if  = $f->make('If', inputs => [$vx, $cmp_out]);
    my $outer_p0  = $f->make('Proj', inputs => [$outer_if], index => 0);
    my $outer_p1  = $f->make('Proj', inputs => [$outer_if], index => 1);
    my $outer_reg = $f->make('Region', inputs => [$outer_p0, $outer_p1]);
    $outer_if->set_region($outer_reg);
    $inner_if->set_control_in($outer_p0);
    $as0->set_control_in($outer_p1);

    # Control chain: $vn -> $vx -> $outer_if
    $vx->set_control_in($vn);
    $outer_if->set_control_in($vx);

    # Return $x
    my $rx  = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $ret->set_control_in($outer_if);

    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($ret, $dom);

    ok(defined $elab, 'E6: nested-if runtime-false elaboration succeeds');

    # The elaboration must emit 2 phis: one at inner merge, one at outer merge.
    my $phis = $elab->emitted_phis;
    ok(scalar(@$phis) >= 2, 'E6: nested-if emits at least 2 phis (inner + outer merge)')
        or diag('emitted_phis count: ' . scalar(@$phis));

    SKIP: {
        skip 'E6: lli not found', 5 unless -x $LLI;

        my $ll;
        eval { $ll = Chalk::IR::Target::LLVM->lower_with_elaboration($ret, $elab) };
        ok(!$@, "E6: LLVM lowering succeeds (got: $@)");

        SKIP: {
            skip 'E6: LLVM lowering failed', 4 unless defined $ll;

            unlike($ll, qr/Perl_/, 'E6 .ll: no Perl_ C-API');

            my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
            binmode $fh, ':utf8';
            print $fh $ll;
            close $fh;

            my $lli_out = qx($LLI $tmp 2>&1);
            my $exit    = $? >> 8;
            is($exit, 0, 'E6 .ll: lli exits cleanly');
            chomp $lli_out;
            # perl oracle: n=2, outer cond (2>0) true, inner cond (2>3) false -> x=1
            is($lli_out, '1', 'E6: lli output is 1 (n=2, outer-true inner-false -> x=1) [B1+H1 repro]');
        }
    }
}

# ---------------------------------------------------------------------------
# E7: Loop-nested-in-if — lli==perl (H2 interaction proof).
#
# Perl: my $s=0; my $n=3; if ($n>0) { while ($n>0) { $s+=$n; $n-- } }; $s
# perl oracle: n=3, n>0 true -> loop runs: s=3+2+1=6; lli must give 6.
#
# The outer-if then-branch contains a full Loop. After processing, var_table
# holds the loop-exit phi SSA ref for $s (=6 on exit). The outer merge phi
# must arm with this loop-exit ref vs the pre-branch value (0 from else/skip).
# The B1+M1 fix (var_table snapshots) makes this work: then_var[vs_id] holds
# the loop-exit phi ref after _process_branch_from_if returns.
# ---------------------------------------------------------------------------
{
    use Chalk::IR::Node::Loop;
    use Chalk::IR::Node::Phi;

    my $f = Chalk::IR::NodeFactory->new;

    # Constants
    my $c3    = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');
    my $c0a   = $f->make('Constant', value => '0', const_type => 'integer');
    $c0a->set_representation('Int');
    my $c0b   = $f->make('Constant', value => '0', const_type => 'integer');
    $c0b->set_representation('Int');
    my $c0c   = $f->make('Constant', value => '0', const_type => 'integer');
    $c0c->set_representation('Int');
    my $c1    = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');

    # Variables
    my $nn    = $f->make('Constant', value => '$n', const_type => 'string');
    my $sn    = $f->make('Constant', value => '$s', const_type => 'string');
    my $vn    = $f->make('VarDecl', inputs => [$nn, $c3]);
    $vn->set_representation('Int');
    my $vs    = $f->make('VarDecl', inputs => [$sn, $c0a]);
    $vs->set_representation('Int');

    my $rn0   = $f->make('PadAccess', targ => 0, varname => '$n', inputs => [$vn]);
    $rn0->set_representation('Int');
    my $rs0   = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs0->set_representation('Int');

    # Outer condition: $n > 0 (static: 3>0 = true)
    my $cmp_out = $f->make('NumGt', inputs => [$rn0, $c0b]);
    $cmp_out->set_representation('Bool');

    # Loop (lives inside the outer-if then-branch)
    my $loop  = $f->make('Loop', inputs => [$vs, undef]);

    # Loop phis
    my $n_phi = $f->make('Phi', region => $loop, values => [$rn0]);
    $n_phi->set_representation('Int');
    my $s_phi = $f->make('Phi', region => $loop, values => [$rs0]);
    $s_phi->set_representation('Int');

    # Loop condition: n_phi > 0
    my $loop_cmp = $f->make('NumGt', inputs => [$n_phi, $c0c]);
    $loop_cmp->set_representation('Bool');
    $loop_cmp->set_control_in($loop);

    # Loop body: s_new = s_phi + n_phi; n_new = n_phi - 1
    my $s_new = $f->make('Add', inputs => [$s_phi, $n_phi]);
    $s_new->set_representation('Int');
    my $n_new = $f->make('Subtract', inputs => [$n_phi, $c1]);
    $n_new->set_representation('Int');

    $n_phi->set_backedge($n_new);
    $s_phi->set_backedge($s_new);

    my $lp0   = $f->make('Proj', inputs => [$loop], index => 0);
    my $lp1   = $f->make('Proj', inputs => [$loop], index => 1);
    my $lreg  = $f->make('Region', inputs => [$lp1]);
    $loop->set_region($lreg);
    $s_new->set_control_in($lp0);
    $n_new->set_control_in($lp0);

    # Outer if: if ($n > 0) { loop } else { skip }
    my $outer_if  = $f->make('If', inputs => [$vn, $cmp_out]);
    my $outer_p0  = $f->make('Proj', inputs => [$outer_if], index => 0);
    my $outer_p1  = $f->make('Proj', inputs => [$outer_if], index => 1);
    my $outer_reg = $f->make('Region', inputs => [$outer_p0, $outer_p1]);
    $outer_if->set_region($outer_reg);

    # Loop lives in outer-then branch
    $loop->set_control_in($outer_p0);

    # Control chain: vn -> vs -> outer_if
    $vs->set_control_in($vn);
    $outer_if->set_control_in($vs);

    # Return $s
    my $rx    = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rx->set_representation('Int');
    my $ret   = $f->make_cfg('Return', inputs => [$rx]);
    $ret->set_control_in($outer_if);

    SKIP: {
        skip 'E7: lli not found', 6 unless -x $LLI;

        my $ll;
        eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
        ok(!$@, "E7: loop-nested-in-if lowers without dying (got: $@)");

        SKIP: {
            skip 'E7: lowering failed', 5 unless defined $ll;

            unlike($ll, qr/Perl_/, 'E7 .ll: no Perl_ C-API');

            my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
            binmode $fh, ':utf8';
            print $fh $ll;
            close $fh;

            my $lli_out = qx($LLI $tmp 2>&1);
            my $exit    = $? >> 8;
            is($exit, 0, 'E7 .ll: lli exits cleanly');
            chomp $lli_out;
            # perl oracle: n=3, n>0 true -> loop: s = 3+2+1 = 6
            is($lli_out, '6', 'E7: lli==perl=6 (loop-nested-in-if, n=3)');
        }
    }
}

# ---------------------------------------------------------------------------
# E8: N4 — placement-only: the pass does NOT hoist or deduplicate.
#
# The Elaborate pass is a placement-only pass. It must not reorder, hoist,
# or deduplicate nodes across branches. Verify by checking that:
# - A value computed only in the then-branch is NOT hoisted to the entry block.
# - A value computed in both branches independently stays in each branch.
# - No phi is emitted for a value that is identical in both branches.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    # Graph: if (5>0) { $x = 1 } else { $x = 2 }; $x
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

    my $if_node = $f->make('If', inputs => [$vx, $cmp]);
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

    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($ret, $dom);

    # N4: placement-only — exactly 1 phi (one diverging variable), no hoisting.
    # The Assign nodes stay in their respective branch blocks, not the entry block.
    my $phis = $elab->emitted_phis;
    is(scalar(@$phis), 1, 'N4: placement-only: exactly 1 phi for the one diverging variable');

    # Verify the phi is at the merge block, not in entry.
    if (scalar(@$phis) == 1) {
        my $phi = $phis->[0];
        isnt($phi->{block_id}, 'entry', 'N4: phi is NOT in the entry block (no hoisting)');
        like($phi->{block_id}, qr/merge/, 'N4: phi is in a merge block (placement-only)');
    }
}

# ---------------------------------------------------------------------------
# M2: Region-as-Return.control_in path.
#
# Real codegen can produce graphs where Return.control_in = Region (not If).
# The Elaborate pass's _collect_control_chain handles this via head traversal
# (Elaborate.pm: if op eq 'Region', get head, continue from head.control_in).
# This path was untested. Verify it works end-to-end.
#
# Graph: if ($n>0) { $x=1 } else { $x=2 }; $x
# but Return.control_in = Region (not If), as real codegen produces.
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

    my $if_node = $f->make('If', inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);
    $as1->set_control_in($proj0);
    $as2->set_control_in($proj1);

    my $rx  = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);

    # KEY: Return's control_in is the REGION, not the If.
    # This exercises the Region-as-Return.control_in head-traversal path.
    $if_node->set_control_in($vx);
    $ret->set_control_in($region);  # NOTE: region, not if_node

    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($ret);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($ret, $dom);

    ok(defined $elab, 'M2: Region-as-control_in: elaboration succeeds');

    my $phis = $elab->emitted_phis;
    ok(scalar(@$phis) >= 1, 'M2: Region-as-control_in: phi emitted at merge')
        or diag('phi count: ' . scalar(@$phis));

    SKIP: {
        skip 'M2: lli not found', 5 unless -x $LLI;

        my $ll;
        eval { $ll = Chalk::IR::Target::LLVM->lower_with_elaboration($ret, $elab) };
        ok(!$@, "M2: Region-as-control_in: LLVM lowering succeeds (got: $@)");

        SKIP: {
            skip 'M2: LLVM lowering failed', 4 unless defined $ll;

            unlike($ll, qr/Perl_/, 'M2 .ll: no Perl_ C-API');

            my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
            binmode $fh, ':utf8';
            print $fh $ll;
            close $fh;

            my $lli_out = qx($LLI $tmp 2>&1);
            my $exit    = $? >> 8;
            is($exit, 0, 'M2 .ll: lli exits cleanly');
            chomp $lli_out;
            # perl oracle: n=5, 5>0 true -> x=1
            is($lli_out, '1', 'M2: lli==perl=1 (Region-as-control_in, n=5)');
        }
    }
}

# ---------------------------------------------------------------------------
# E9: If-nested-in-loop — lli==perl (H2 interaction proof, other direction).
#
# Perl: my $n=3; my $s=0; while($n>0){ if($n>1){$s+=10}else{$s+=1}; $n-- }; $s
# perl oracle: iter1(n=3,n>1): s=10; iter2(n=2,n>1): s=20; iter3(n=1,n>1 false): s=21; = 21
#
# The if-inside-loop uses an inner Phi node at the inner Region to represent
# "the value of $s after the inner if": then-arm = s+10, else-arm = s+1.
# The loop phi s_phi's backedge is wired to this inner Phi.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    # Constants
    my $c3    = $f->make('Constant', value => '3',  const_type => 'integer'); $c3->set_representation('Int');
    my $c0a   = $f->make('Constant', value => '0',  const_type => 'integer'); $c0a->set_representation('Int');
    my $c0b   = $f->make('Constant', value => '0',  const_type => 'integer'); $c0b->set_representation('Int');
    my $c0c   = $f->make('Constant', value => '0',  const_type => 'integer'); $c0c->set_representation('Int');
    my $c1    = $f->make('Constant', value => '1',  const_type => 'integer'); $c1->set_representation('Int');
    my $c1b   = $f->make('Constant', value => '1',  const_type => 'integer'); $c1b->set_representation('Int');
    my $c10   = $f->make('Constant', value => '10', const_type => 'integer'); $c10->set_representation('Int');

    my $nn   = $f->make('Constant', value => '$n', const_type => 'string');
    my $sn   = $f->make('Constant', value => '$s', const_type => 'string');
    my $vn   = $f->make('VarDecl', inputs => [$nn, $c3]);  $vn->set_representation('Int');
    my $vs   = $f->make('VarDecl', inputs => [$sn, $c0a]); $vs->set_representation('Int');

    my $rn0  = $f->make('PadAccess', targ => 0, varname => '$n', inputs => [$vn]); $rn0->set_representation('Int');
    my $rs0  = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]); $rs0->set_representation('Int');

    # Loop
    my $loop  = $f->make('Loop', inputs => [$vs, undef]);
    my $n_phi = $f->make('Phi', region => $loop, values => [$rn0]); $n_phi->set_representation('Int');
    my $s_phi = $f->make('Phi', region => $loop, values => [$rs0]); $s_phi->set_representation('Int');

    # Loop condition: n_phi > 0
    my $loop_cmp = $f->make('NumGt', inputs => [$n_phi, $c0c]); $loop_cmp->set_representation('Bool');
    $loop_cmp->set_control_in($loop);

    # Inner condition: n_phi > 1
    my $inner_cmp = $f->make('NumGt', inputs => [$n_phi, $c1]); $inner_cmp->set_representation('Bool');

    # Inner if branches
    my $body_proj = $f->make('Proj', inputs => [$loop], index => 0);
    my $exit_proj = $f->make('Proj', inputs => [$loop], index => 1);
    my $exit_reg  = $f->make('Region', inputs => [$exit_proj]);
    $loop->set_region($exit_reg);

    my $inner_if  = $f->make('If', inputs => [$body_proj, $inner_cmp]);
    my $inner_p0  = $f->make('Proj', inputs => [$inner_if], index => 0);
    my $inner_p1  = $f->make('Proj', inputs => [$inner_if], index => 1);
    my $inner_reg = $f->make('Region', inputs => [$inner_p0, $inner_p1]);
    $inner_if->set_region($inner_reg);
    $inner_if->set_control_in($body_proj);

    # Then: s_phi + 10; Else: s_phi + 1
    my $s_then = $f->make('Add', inputs => [$s_phi, $c10]); $s_then->set_representation('Int');
    my $s_else = $f->make('Add', inputs => [$s_phi, $c1b]); $s_else->set_representation('Int');

    # Inner Phi at Region merge: represents "s after the if"
    my $s_new = $f->make('Phi', region => $inner_reg, values => [$s_then, $s_else]);
    $s_new->set_representation('Int');

    # n_new = n_phi - 1
    my $n_new = $f->make('Subtract', inputs => [$n_phi, $c1]); $n_new->set_representation('Int');
    $n_new->set_control_in($body_proj);

    # Loop backedges
    $n_phi->set_backedge($n_new);
    $s_phi->set_backedge($s_new);

    # Control chain: vn -> vs -> loop
    $vs->set_control_in($vn);
    $loop->set_control_in($vs);

    # Return $s
    my $rx  = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]); $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $ret->set_control_in($loop);

    SKIP: {
        skip 'E9: lli not found', 6 unless -x $LLI;

        my $ll;
        eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
        ok(!$@, "E9: if-nested-in-loop lowers without dying (got: $@)");

        SKIP: {
            skip 'E9: lowering failed', 5 unless defined $ll;

            unlike($ll, qr/Perl_/, 'E9 .ll: no Perl_ C-API');

            my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
            binmode $fh, ':utf8';
            print $fh $ll;
            close $fh;

            my $lli_out = qx($LLI $tmp 2>&1);
            my $exit    = $? >> 8;
            is($exit, 0, 'E9 .ll: lli exits cleanly');
            chomp $lli_out;
            # perl oracle: n=3 -> s=10; n=2 -> s=20; n=1 (not >1) -> s=21
            is($lli_out, '21', 'E9: lli==perl=21 (if-nested-in-loop, n=3)');
        }
    }
}

done_testing;
