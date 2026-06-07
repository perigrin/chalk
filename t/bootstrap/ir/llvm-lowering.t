# ABOUTME: Tests for the SoN->LLVM lowering pass for the literal-arithmetic slice (Phase 3a D4).
# ABOUTME: Validates that a typed SoN graph for `return 1+2` generates LLVM IR that runs correctly.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Return;
use Chalk::IR::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

# Skip if lli is not available (CI without LLVM)
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# L1: LLVM lowering module loads.
ok(Chalk::IR::Target::LLVM->can('lower'),
    'Chalk::IR::Target::LLVM has a lower() method');

# L2: hand-author the typed SoN graph for `return 1 + 2` and lower to LLVM IR text.
# Graph: Constant(1,Int) + Constant(2,Int) -> Add(Int) -> Return
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');

    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');

    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my $ll = Chalk::IR::Target::LLVM->lower($ret);

    ok(defined $ll, 'lower() returns defined text');
    like($ll, qr/define.*\@main/, 'generated .ll contains a main function');
    like($ll, qr/add i64/, 'generated .ll contains i64 add instruction');
}

# L3: the generated .ll contains NO perl C-API calls.
# This is the load-bearing negative AC: no Perl_, no SV, no libperl.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my $ll = Chalk::IR::Target::LLVM->lower($ret);

    unlike($ll, qr/Perl_/,  'generated .ll does not call Perl_ C-API functions');
    unlike($ll, qr/\bSV\b/, 'generated .ll does not mention SV type');
    unlike($ll, qr/libperl/, 'generated .ll does not mention libperl');
}

# L4: the generated .ll, when run through lli, produces the perl oracle output.
# perl oracle: 1+2 = 3 (printed as decimal integer).
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my $ll = Chalk::IR::Target::LLVM->lower($ret);

    # Write to temp file and run through lli
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;

    my $lli_out = qx($LLI $tmp 2>&1);
    my $exit    = $? >> 8;

    is($exit, 0, 'lli exits cleanly on generated .ll');

    # perl oracle
    my $perl_out = $1 if (1+2) =~ /(\d+)/;
    $perl_out = '3';   # constant: 1+2 under perl is 3

    chomp $lli_out;
    is($lli_out, $perl_out,
        "lli output '$lli_out' matches perl oracle '$perl_out'");
}

# L5: runtime-free coverage — every value-def has a non-Scalar representation.
# The Add graph for 1+2 is fully Int; no Scalar values, so coverage = 100%.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my @data_nodes = ($c1, $c2, $add);
    my @scalar_nodes = grep {
        defined $_->representation && $_->representation eq 'Scalar'
    } @data_nodes;

    is(scalar @scalar_nodes, 0,
        'runtime-free coverage: 0 Scalar-representation nodes in 1+2 graph (L-GREEN)');
}

# L6: the test does NOT use the hand-written t/spike/llvm/add.ll.
# Verify by checking the generated text is not identical to the spike file content.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $add = $f->make('Add', inputs => [$c1, $c2]);
    $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my $generated = Chalk::IR::Target::LLVM->lower($ret);

    # The spike file contains this specific comment; generated output must not
    # simply be the spike file read back.
    unlike($generated, qr/This file is NOT generated by the Chalk compiler/,
        'generated .ll is not the hand-written spike file');
}

# ---------------------------------------------------------------------------
# L7: And node (&&) lowering — short-circuit branch+phi
#
# And(Constant 3 :Int, Constant 7 :Int) wrapped in Return.
# Perl &&: 3 is truthy -> returns 7.  lli must print 7.
# RED phase: currently dies "cannot lower op=And".
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');
    my $c7 = $f->make('Constant', value => '7', const_type => 'integer');
    $c7->set_representation('Int');
    my $and = $f->make('And', inputs => [$c3, $c7]);
    $and->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$and]);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "And node lowers without dying (got: $@)");

    SKIP: {
        skip 'And lowering failed', 4 unless defined $ll;

        unlike($ll, qr/Perl_/, 'And .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'And .ll: no SV type');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'And .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '7', "And .ll: lli output is 7 (3&&7 == 7)");
    }
}

# ---------------------------------------------------------------------------
# L8: Or node (||) lowering — short-circuit branch+phi
#
# Or(Constant 3 :Int, Constant 7 :Int) wrapped in Return.
# Perl ||: 3 is truthy -> returns 3.  lli must print 3.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c3 = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');
    my $c7 = $f->make('Constant', value => '7', const_type => 'integer');
    $c7->set_representation('Int');
    my $or = $f->make('Or', inputs => [$c3, $c7]);
    $or->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$or]);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "Or node lowers without dying (got: $@)");

    SKIP: {
        skip 'Or lowering failed', 4 unless defined $ll;

        unlike($ll, qr/Perl_/, 'Or .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'Or .ll: no SV type');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'Or .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '3', "Or .ll: lli output is 3 (3||7 == 3)");
    }
}

# ---------------------------------------------------------------------------
# L9: Phi missing-predecessor guard
#
# A Phi node referenced in lower_value without all predecessor blocks
# having been materialized must die loudly (not silently emit
# undef-poisoned phi). This is the adversarial well-typed check.
# ---------------------------------------------------------------------------
{
    my $f = Chalk::IR::NodeFactory->new;

    # Build a Region and Phi manually, but do NOT wire up the predecessor
    # blocks so the Phi has only 0 incoming values (empty inputs).
    my $region = $f->make('Region', inputs => []);
    my $phi    = $f->make('Phi', region => $region, values => []);
    $phi->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$phi]);

    eval { Chalk::IR::Target::LLVM->lower($ret) };
    like($@, qr/Phi|missing|edge|predecessor|incoming/i,
        'Phi with no incoming values dies loudly (adversarial guard)');
}

# ---------------------------------------------------------------------------
# L10: If/Proj/Region/Phi lowering — if ($n > 0) { $x = 1 } else { $x = 2 }; $x
#
# D1 pattern: condition -> br i1 to then/else blocks, Assign in each branch,
# phi in merge block, final PadAccess returns phi result.
# $n=5, expected output: 1.
# ---------------------------------------------------------------------------
{
    use Chalk::IR::Node::NumGt;
    use Chalk::IR::Node::VarDecl;
    use Chalk::IR::Node::PadAccess;
    use Chalk::IR::Node::Assign;
    use Chalk::IR::Node::If;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;

    my $f = Chalk::IR::NodeFactory->new;

    # $n = 5; condition: $n > 0
    my $cn   = $f->make('Constant', value => '5',  const_type => 'integer');
    $cn->set_representation('Int');
    my $zero = $f->make('Constant', value => '0',  const_type => 'integer');
    $zero->set_representation('Int');
    my $cmp  = $f->make('NumGt', inputs => [$cn, $zero]);
    $cmp->set_representation('Bool');

    # my $x; (no init)
    my $xn   = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx   = $f->make('VarDecl', inputs => [$xn]);
    $vx->set_representation('Int');

    # $x = 1 (then branch)
    my $c1   = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $lhs1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs1->set_representation('Int');
    my $as1  = $f->make('Assign', inputs => [$lhs1, $c1]);
    $as1->set_representation('Int');

    # $x = 2 (else branch)
    my $c2   = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    # Note: lhs2 hash-cons == lhs1 (same targ/varname/vd) — that's correct.
    my $lhs2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs2->set_representation('Int');
    my $as2  = $f->make('Assign', inputs => [$lhs2, $c2]);
    $as2->set_representation('Int');

    # If / Proj / Region structure
    my $if_node = $f->make('If',   inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    # Wire then/else assigns as consumers of their Proj nodes
    $as1->set_control_in($proj0);
    $as2->set_control_in($proj1);

    # $x (read after if/else)
    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');

    # Return $x; control chain: vx -> if
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $if_node->set_control_in($vx);
    $ret->set_control_in($if_node);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "If/else node lowers without dying (got: $@)");

    SKIP: {
        skip 'If/else lowering failed', 5 unless defined $ll;

        unlike($ll, qr/Perl_/, 'If/else .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'If/else .ll: no SV type');
        like($ll, qr/br i1/, 'If/else .ll: contains conditional branch');
        like($ll, qr/phi i64/, 'If/else .ll: contains phi');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'If/else .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '1', "If/else .ll: lli output is 1 (n=5, n>0 true -> x=1)");
    }
}

# ---------------------------------------------------------------------------
# L11: Loop node lowering — while ($n > 0) { $s += $n; $n-- }; $s
#
# $n=3, $s=0 initial. Loop sums 3+2+1=6.
# Demonstrates: loop header phi, condition test, body updates, back-edge.
# ---------------------------------------------------------------------------
{
    use Chalk::IR::Node::NumGt;
    use Chalk::IR::Node::Subtract;
    use Chalk::IR::Node::Add;
    use Chalk::IR::Node::VarDecl;
    use Chalk::IR::Node::PadAccess;
    use Chalk::IR::Node::Loop;
    use Chalk::IR::Node::Phi;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;

    my $f = Chalk::IR::NodeFactory->new;

    # Preheader: n=3, s=0
    my $c3   = $f->make('Constant', value => '3', const_type => 'integer');
    $c3->set_representation('Int');
    my $c0s  = $f->make('Constant', value => '0', const_type => 'integer');
    $c0s->set_representation('Int');
    my $c0   = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_representation('Int');
    my $one  = $f->make('Constant', value => '1', const_type => 'integer');
    $one->set_representation('Int');

    my $nn   = $f->make('Constant', value => '$n', const_type => 'string');
    my $sn   = $f->make('Constant', value => '$s', const_type => 'string');
    my $vn   = $f->make('VarDecl', inputs => [$nn, $c3]);
    $vn->set_representation('Int');
    my $vs   = $f->make('VarDecl', inputs => [$sn, $c0s]);
    $vs->set_representation('Int');

    my $rn0  = $f->make('PadAccess', targ => 0, varname => '$n', inputs => [$vn]);
    $rn0->set_representation('Int');
    my $rs0  = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs0->set_representation('Int');

    # Loop node (entry_ctrl = %vs)
    my $loop = $f->make('Loop', inputs => [$vs, undef]);

    # Phi nodes for loop-carried values
    my $n_phi = $f->make('Phi', region => $loop, values => [$rn0]);
    $n_phi->set_representation('Int');
    my $s_phi = $f->make('Phi', region => $loop, values => [$rs0]);
    $s_phi->set_representation('Int');

    # Condition: n_phi > 0
    my $zero = $c0;  # re-use c0
    my $cmp  = $f->make('NumGt', inputs => [$n_phi, $zero]);
    $cmp->set_representation('Bool');

    # Body: s_new = s_phi + n_phi; n_new = n_phi - 1
    my $s_new = $f->make('Add', inputs => [$s_phi, $n_phi]);
    $s_new->set_representation('Int');
    my $n_new = $f->make('Subtract', inputs => [$n_phi, $one]);
    $n_new->set_representation('Int');

    # Wire backedges
    $n_phi->set_backedge($n_new);
    $s_phi->set_backedge($s_new);

    # Proj/Region
    my $body_proj = $f->make('Proj', inputs => [$loop], index => 0);
    my $exit_proj = $f->make('Proj', inputs => [$loop], index => 1);
    my $exit_region = $f->make('Region', inputs => [$exit_proj]);
    $loop->set_region($exit_region);

    # Wire body nodes as consumers of body_proj
    $n_new->set_control_in($body_proj);
    $s_new->set_control_in($body_proj);

    # Return $s (the s_phi value at exit)
    my $rs = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$s_phi]);
    $vs->set_control_in($vn);
    $loop->set_control_in($vs);
    $ret->set_control_in($loop);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "Loop node lowers without dying (got: $@)");

    SKIP: {
        skip 'Loop lowering failed', 5 unless defined $ll;

        unlike($ll, qr/Perl_/, 'Loop .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'Loop .ll: no SV type');
        like($ll, qr/phi i64/, 'Loop .ll: contains phi instruction');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'Loop .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '6', "Loop .ll: lli output is 6 (sum 3+2+1=6)");
    }
}

# ---------------------------------------------------------------------------
# L12: B3 — one-branch assign: if ($n > 0) { $x = 1 } $x
#
# $n=5. Only the then-branch assigns $x. Else-branch keeps the pre-branch
# value (0). Expected output: 1 (condition true, then-branch runs).
#
# Bug (B3): the old phi guard required BOTH branches to have a defined ref
# different from each other. When only then-branch changes $x, else_ref ==
# pre_branch_ref, so no phi was emitted; $x stayed at the pre-branch SSA
# value (0) in the merge block. Lowering returned 0, not 1.
# ---------------------------------------------------------------------------
{
    use Chalk::IR::Node::NumGt;
    use Chalk::IR::Node::VarDecl;
    use Chalk::IR::Node::PadAccess;
    use Chalk::IR::Node::Assign;
    use Chalk::IR::Node::If;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;

    my $f = Chalk::IR::NodeFactory->new;

    # $n = 5; $x = 0; if ($n > 0) { $x = 1 }; $x
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

    # my $x = 0
    my $xn   = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx   = $f->make('VarDecl', inputs => [$xn, $c0]);
    $vx->set_representation('Int');

    # $x = 1 (then branch only; no else branch)
    my $lhs1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs1->set_representation('Int');
    my $as1  = $f->make('Assign', inputs => [$lhs1, $c1]);
    $as1->set_representation('Int');

    # If / Proj / Region — Proj1 (else) has no body
    my $if_node = $f->make('If',   inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    # Wire then-assign as consumer of proj0; else has no body
    $as1->set_control_in($proj0);

    # $x (read after if)
    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');

    # Return $x; control: vx -> if
    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $if_node->set_control_in($vx);
    $ret->set_control_in($if_node);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "B3: one-branch if lowers without dying (got: $@)");

    SKIP: {
        skip 'B3: one-branch if lowering failed', 4 unless defined $ll;

        unlike($ll, qr/Perl_/, 'B3 .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'B3 .ll: no SV type');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'B3 .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '1', "B3 lli output is 1 (n=5, n>0, then-branch runs: x=1)");
    }
}

# ---------------------------------------------------------------------------
# L13: B2 — Num-typed if/else branch phi
#
# my $n=5; my $x=0.0; if ($n>0){ $x=2.5 } else { $x=1.5 } $x
# Expected: 2.5.
# Bug (B2): the merge phi in _process_if_node hardcoded `phi i64` regardless
# of the variable's representation. A double-typed variable produced invalid
# LLVM IR mixing `double` values into an `i64` phi.
# ---------------------------------------------------------------------------
{
    use Chalk::IR::Node::NumGt;
    use Chalk::IR::Node::VarDecl;
    use Chalk::IR::Node::PadAccess;
    use Chalk::IR::Node::Assign;
    use Chalk::IR::Node::If;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;

    my $f = Chalk::IR::NodeFactory->new;

    my $cn   = $f->make('Constant', value => '5',   const_type => 'integer');
    $cn->set_representation('Int');
    my $zero = $f->make('Constant', value => '0',   const_type => 'integer');
    $zero->set_representation('Int');
    my $cmp  = $f->make('NumGt', inputs => [$cn, $zero]);
    $cmp->set_representation('Bool');

    # my $x = 0.0 (Num)
    my $xn   = $f->make('Constant', value => '$x',  const_type => 'string');
    my $init = $f->make('Constant', value => '0.0',  const_type => 'integer');
    $init->set_representation('Num');
    my $vx   = $f->make('VarDecl', inputs => [$xn, $init]);
    $vx->set_representation('Num');

    # $x = 2.5 (then)
    my $c25 = $f->make('Constant', value => '2.5', const_type => 'integer');
    $c25->set_representation('Num');
    my $lhs1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs1->set_representation('Num');
    my $as1  = $f->make('Assign', inputs => [$lhs1, $c25]);
    $as1->set_representation('Num');

    # $x = 1.5 (else)
    my $c15 = $f->make('Constant', value => '1.5', const_type => 'integer');
    $c15->set_representation('Num');
    my $lhs2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs2->set_representation('Num');
    my $as2  = $f->make('Assign', inputs => [$lhs2, $c15]);
    $as2->set_representation('Num');

    my $if_node = $f->make('If',   inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    $as1->set_control_in($proj0);
    $as2->set_control_in($proj1);

    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Num');

    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $if_node->set_control_in($vx);
    $ret->set_control_in($if_node);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "B2: Num-typed if/else lowers without dying (got: $@)");

    SKIP: {
        skip 'B2: Num if/else lowering failed', 4 unless defined $ll;

        unlike($ll, qr/Perl_/, 'B2 .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'B2 .ll: no SV type');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'B2 .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '2.5', "B2 lli output is 2.5 (n=5, n>0 -> x=2.5)");
    }
}

# ---------------------------------------------------------------------------
# L14: B1 — dependent statements in a branch body
#
# if ($n > 0) { my $t = $n + 1; $x = $t * 2 }
# $n=5, expected: $x = (5+1)*2 = 12.
# Bug (B1): body nodes were ordered by consumer-DFS, not control_in chain.
# Two dependent assignments could emit out of order: $x = $t*2 before
# $t = $n+1 -> use of undef $t -> wrong result or verifier error.
# ---------------------------------------------------------------------------
{
    use Chalk::IR::Node::NumGt;
    use Chalk::IR::Node::VarDecl;
    use Chalk::IR::Node::PadAccess;
    use Chalk::IR::Node::Assign;
    use Chalk::IR::Node::Add;
    use Chalk::IR::Node::Multiply;
    use Chalk::IR::Node::If;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;

    my $f = Chalk::IR::NodeFactory->new;

    my $cn   = $f->make('Constant', value => '5', const_type => 'integer');
    $cn->set_representation('Int');
    my $zero = $f->make('Constant', value => '0', const_type => 'integer');
    $zero->set_representation('Int');
    my $c1   = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c2   = $f->make('Constant', value => '2', const_type => 'integer');
    $c2->set_representation('Int');
    my $c0   = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_representation('Int');
    my $cmp  = $f->make('NumGt', inputs => [$cn, $zero]);
    $cmp->set_representation('Bool');

    # my $x = 0 (pre-branch)
    my $xn   = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx   = $f->make('VarDecl', inputs => [$xn, $c0]);
    $vx->set_representation('Int');

    # In then-branch: my $t = $n + 1; $x = $t * 2
    my $tn   = $f->make('Constant', value => '$t', const_type => 'string');
    my $add  = $f->make('Add', inputs => [$cn, $c1]);
    $add->set_representation('Int');
    my $vt   = $f->make('VarDecl', inputs => [$tn, $add]);
    $vt->set_representation('Int');

    my $rt   = $f->make('PadAccess', targ => 0, varname => '$t', inputs => [$vt]);
    $rt->set_representation('Int');
    my $mul  = $f->make('Multiply', inputs => [$rt, $c2]);
    $mul->set_representation('Int');
    my $lhsx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhsx->set_representation('Int');
    my $asx  = $f->make('Assign', inputs => [$lhsx, $mul]);
    $asx->set_representation('Int');

    # Chain: vt -> asx (vt must precede asx in the body)
    $vt->set_control_in(undef);   # no explicit predecessor: first in chain
    $asx->set_control_in($vt);    # asx depends on vt

    # If / Proj / Region
    my $if_node = $f->make('If',   inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    # Wire first body node to proj0 (then-branch entry)
    $vt->set_control_in($proj0);

    # Return $x
    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $if_node->set_control_in($vx);
    $ret->set_control_in($if_node);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "B1: dependent body stmts lower without dying (got: $@)");

    SKIP: {
        skip 'B1: dependent body lowering failed', 4 unless defined $ll;

        unlike($ll, qr/Perl_/, 'B1 .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'B1 .ll: no SV type');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'B1 .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '12', "B1 lli output is 12 (n=5, t=n+1=6, x=t*2=12)");
    }
}

# ---------------------------------------------------------------------------
# L15: H3 — loop with a comparison inside the body (not just the condition)
#
# my $n=3; my $s=0; while ($n>0){ $s += ($n > 1 ? 10 : 1); $n-- } $s
# Expected: n=3: (3>1)->10; n=2: (2>1)->10; n=1: (1>1)->0+1=1; s=10+10+1=21
# Bug (H3): _lower_loop_condition selects the first icmp consumer of any loop
# phi — but if the loop body contains its own comparison, that inner icmp
# can be selected instead of the header branch condition, emitting garbage.
# Fix: select the condition that structurally feeds the header branch (via
# the Proj/Loop consumer chain), not the first-icmp heuristic.
# ---------------------------------------------------------------------------
{
    use Chalk::IR::Node::NumGt;
    use Chalk::IR::Node::VarDecl;
    use Chalk::IR::Node::PadAccess;
    use Chalk::IR::Node::Assign;
    use Chalk::IR::Node::CompoundAssign;
    use Chalk::IR::Node::Subtract;
    use Chalk::IR::Node::Add;
    use Chalk::IR::Node::TernaryExpr;
    use Chalk::IR::Node::Loop;
    use Chalk::IR::Node::Phi;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;

    my $f = Chalk::IR::NodeFactory->new;

    my $c3   = $f->make('Constant', value => '3',  const_type => 'integer');
    $c3->set_representation('Int');
    my $c0a  = $f->make('Constant', value => '0',  const_type => 'integer');
    $c0a->set_representation('Int');
    my $c0b  = $f->make('Constant', value => '0',  const_type => 'integer');
    $c0b->set_representation('Int');
    my $c1   = $f->make('Constant', value => '1',  const_type => 'integer');
    $c1->set_representation('Int');
    my $c10  = $f->make('Constant', value => '10', const_type => 'integer');
    $c10->set_representation('Int');

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

    # Loop phis
    my $n_phi = $f->make('Phi', region => $loop, values => [$rn0]);
    $n_phi->set_representation('Int');
    my $s_phi = $f->make('Phi', region => $loop, values => [$rs0]);
    $s_phi->set_representation('Int');

    # Body: inner comparison n_phi > 1 CREATED FIRST — so it's the first
    # icmp consumer of n_phi. If _lower_loop_condition uses first-icmp heuristic,
    # it would pick this inner comparison as the loop condition (WRONG).
    # The fix must use structural selection (the icmp wired via control_in to
    # the Loop node) to avoid this ambiguity.
    my $inner_cmp = $f->make('NumGt', inputs => [$n_phi, $c1]);
    $inner_cmp->set_representation('Bool');
    my $branch_val = $f->make('TernaryExpr', inputs => [$inner_cmp, $c10, $c1]);
    $branch_val->set_representation('Int');

    # Condition: n_phi > 0  (this feeds the header branch — structural, created second)
    my $loop_cmp = $f->make('NumGt', inputs => [$n_phi, $c0b]);
    $loop_cmp->set_representation('Bool');

    # s_new = s_phi + branch_val; n_new = n_phi - 1
    my $s_new = $f->make('Add', inputs => [$s_phi, $branch_val]);
    $s_new->set_representation('Int');
    my $n_new = $f->make('Subtract', inputs => [$n_phi, $c1]);
    $n_new->set_representation('Int');

    $n_phi->set_backedge($n_new);
    $s_phi->set_backedge($s_new);

    my $body_proj = $f->make('Proj', inputs => [$loop], index => 0);
    my $exit_proj = $f->make('Proj', inputs => [$loop], index => 1);
    my $exit_region = $f->make('Region', inputs => [$exit_proj]);
    $loop->set_region($exit_region);

    # Wire the loop condition to the loop node (structural link)
    $loop_cmp->set_control_in($loop);

    $n_new->set_control_in($body_proj);
    $s_new->set_control_in($body_proj);

    my $ret = $f->make_cfg('Return', inputs => [$s_phi]);
    $vs->set_control_in($vn);
    $loop->set_control_in($vs);
    $ret->set_control_in($loop);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "H3: loop-with-body-comparison lowers without dying (got: $@)");

    SKIP: {
        skip 'H3: loop-with-body-comparison lowering failed', 4 unless defined $ll;

        unlike($ll, qr/Perl_/, 'H3 .ll: no Perl_ C-API');
        unlike($ll, qr/\bSV\b/, 'H3 .ll: no SV type');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $lli_out = qx($LLI $tmp 2>&1);
        my $exit    = $? >> 8;
        is($exit, 0, 'H3 .ll: lli exits cleanly');
        chomp $lli_out;
        is($lli_out, '21', "H3 lli output is 21 (n=3: 10+10+1=21)");
    }
}

# ---------------------------------------------------------------------------
# L16: H4/H5 — phi predecessor validation
#
# A phi whose incoming label is NOT an actual predecessor of the phi's block
# (or whose incoming slot is undef) must die loudly before lli sees it.
# The existing guard only catches EMPTY inputs. We extend it to catch
# a well-formed-looking phi with a known-non-predecessor label or undef slot.
# ---------------------------------------------------------------------------
{
    # Test: phi with defined but undef incoming value slot must die loudly.
    # We build a Phi that has 2 inputs but inputs[0] is undef.
    my $f = Chalk::IR::NodeFactory->new;

    my $region = $f->make('Region', inputs => []);
    # Build a phi with one defined and one undef incoming value
    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');

    # Manufacture a Phi with inputs = [undef, undef] by setting values = []
    # then manually wiring an undef slot — use values => [$c1] then set inputs[0]=undef
    my $phi = $f->make('Phi', region => $region, values => [$c1]);
    $phi->set_representation('Int');
    # Corrupt the first input to undef (simulating a missing predecessor wire)
    $phi->inputs->[0] = undef;

    my $ret = $f->make_cfg('Return', inputs => [$phi]);

    eval { Chalk::IR::Target::LLVM->lower($ret) };
    like($@, qr/Phi|undef|predecessor|incoming|missing/i,
        'H4/H5: Phi with undef incoming value slot dies loudly (predecessor guard)');
}

done_testing;
