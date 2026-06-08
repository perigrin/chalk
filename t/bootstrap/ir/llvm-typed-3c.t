# ABOUTME: Tests for Phase 3c typed-IR lowering: arith-div, arith-mod, VarDecl/PadAccess SSA model.
# ABOUTME: Each group is a RED->GREEN TDD cycle; tests cover Num representation and mutable scalars.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Coerce;
use Chalk::IR::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# ---------------------------------------------------------------------------
# Helper: run .ll through lli; return (stdout_chomped, exit_code).
# ---------------------------------------------------------------------------
sub run_lli {
    my ($ll) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

# Helper: make Int constant node
sub int_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

# Helper: make Num constant node
sub num_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'number');
    $c->set_representation('Num');
    return $c;
}

# ===========================================================================
# GROUP 1: arith-div — Perl `/` is float division
#
# `3 / 4` under Perl = 0.75 (not 0 as truncating int division).
# The correct lowering: Coerce(Int->Num) both operands, fdiv double, print %g.
# ===========================================================================

# DIV-1: Divide node with Num representation lowers to fdiv double.
{
    my $f = Chalk::IR::NodeFactory->new;

    # Build: Return(Divide(Coerce[Int->Num](3), Coerce[Int->Num](4)))
    # The Divide op has representation Num.
    my $c3   = int_const($f, 3);
    my $c4   = int_const($f, 4);
    my $coe3 = $f->make('Coerce', inputs => [$c3], from_repr => 'Int', to_repr => 'Num');
    $coe3->set_representation('Num');
    my $coe4 = $f->make('Coerce', inputs => [$c4], from_repr => 'Int', to_repr => 'Num');
    $coe4->set_representation('Num');

    my $div = $f->make('Divide', inputs => [$coe3, $coe4]);
    $div->set_representation('Num');

    my $ret = $f->make_cfg('Return', inputs => [$div]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "arith-div DIV-1: Divide(Num) lowers without dying")
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        like($ll, qr/fdiv double/, 'arith-div DIV-1: .ll contains fdiv double');
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'arith-div DIV-1: .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'arith-div DIV-1: lli exits 0');
        is($out, 'Num:0.75', "arith-div DIV-1: lli output 'Num:0.75' matches perl oracle (type-tagged)");
    }
}

# DIV-2: Divide with Int representation must still reject (not a silent miscompile).
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c3  = int_const($f, 3);
    my $c4  = int_const($f, 4);
    my $div = $f->make('Divide', inputs => [$c3, $c4]);
    $div->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$div]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok($@, 'arith-div DIV-2: Divide with Int repr still dies (preserves correctness guard)');
    like($@, qr/GAP|Divide.*Int|not.*float/i,
        'arith-div DIV-2: error message mentions Divide or Int repr problem');
}

# ===========================================================================
# GROUP 2: arith-mod — Perl `%` follows the right-operand sign
#
# `-7 % 3` under Perl = 2 (not -1 as LLVM srem gives).
# The sign-correction formula:
#   t = a srem b
#   if (t != 0 && (t xor b) < 0) then t = t + b
# ===========================================================================

# MOD-1: Modulo node with Int representation and sign-correction lowers to perl-semantics modulo.
{
    my $f = Chalk::IR::NodeFactory->new;

    # Build: Return(Modulo(Constant(-7, Int), Constant(3, Int))) with Int representation.
    # Perl: -7 % 3 = 2.
    my $cm7 = int_const($f, -7);
    my $c3  = int_const($f, 3);
    my $mod = $f->make('Modulo', inputs => [$cm7, $c3]);
    $mod->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$mod]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'arith-mod MOD-1: Modulo(Int,Int) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 4 unless defined $ll;
        like($ll, qr/srem i64/, 'arith-mod MOD-1: .ll contains srem i64');
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'arith-mod MOD-1: .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'arith-mod MOD-1: lli exits 0');
        is($out, 'Int:2', "arith-mod MOD-1: lli output 'Int:2' matches perl oracle (-7 % 3 == 2, type-tagged)");
    }
}

# MOD-2: Modulo with positive operands should also be correct (7 % 3 = 1).
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c7  = int_const($f, 7);
    my $c3  = int_const($f, 3);
    my $mod = $f->make('Modulo', inputs => [$c7, $c3]);
    $mod->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$mod]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'arith-mod MOD-2: Modulo(7,3) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 2 unless defined $ll;
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'arith-mod MOD-2: lli exits 0');
        is($out, 'Int:1', "arith-mod MOD-2: lli output 'Int:1' matches perl oracle (7 % 3 == 1, type-tagged)");
    }
}

# MOD-3: Modulo with negative RHS: 7 % -3 under Perl = -2.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c7   = int_const($f, 7);
    my $cm3  = int_const($f, -3);
    my $mod  = $f->make('Modulo', inputs => [$c7, $cm3]);
    $mod->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$mod]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'arith-mod MOD-3: Modulo(7,-3) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 2 unless defined $ll;
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'arith-mod MOD-3: lli exits 0');
        is($out, 'Int:-2', "arith-mod MOD-3: lli output 'Int:-2' matches perl oracle (7 % -3 == -2, type-tagged)");
    }
}

# ===========================================================================
# GROUP 3: VarDecl / PadAccess — SSA-value threading for lexical scalars
#
# Design: the LLVM backend uses SSA-value threading (not alloca+store+load)
# for straight-line code. VarDecl stores the initializer's SSA value in a
# "var table" keyed by the VarDecl node's id. PadAccess looks up its VarDecl
# (via inputs->[0]) in the var table and returns that SSA value.
# Assign updates the var table entry for its target VarDecl.
#
# Graph wiring convention for hand-authored test graphs:
#   PadAccess.inputs[0] = the VarDecl node (find-by-reference)
#   Assign.inputs[0]    = the PadAccess node (target lvalue)
#   Assign.inputs[1]    = the new value node
#
# Control-chain processing: the lower() function walks the control chain
# (via control_in) to process side-effect Assign nodes BEFORE lowering
# the Return value. VarDecl and Assign are side-effect nodes in the control
# chain; PadAccess is a pure value read.
# ===========================================================================

# VAR-1 (A1): my $x = 1; return $x
# Graph: VarDecl($x, Constant(1)) → PadAccess($x) → Return
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1   = int_const($f, 1);
    my $vd   = $f->make('VarDecl', inputs => [
        $f->make('Constant', value => 'x', const_type => 'string'),
        $c1
    ]);
    $vd->set_representation('Int');

    # PadAccess: inputs[0] = VarDecl (the source slot)
    my $pad  = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vd]);
    $pad->set_representation('Int');

    my $ret  = $f->make_cfg('Return', inputs => [$pad]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'VAR-1 (A1): my $x=1; return $x — lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 4 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'VAR-1 (A1): .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'VAR-1 (A1): lli exits 0');
        is($out, 'Int:1', "VAR-1 (A1): lli output 'Int:1' matches perl oracle (type-tagged)");
    }
}

# VAR-2 (C1): my $x = 1; $x = 2; return $x
# Graph: VarDecl($x, 1) → Assign($x, 2) [in control chain] → PadAccess($x) → Return
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1   = int_const($f, 1);
    my $c2   = int_const($f, 2);
    my $vd   = $f->make('VarDecl', inputs => [
        $f->make('Constant', value => 'x', const_type => 'string'),
        $c1
    ]);
    $vd->set_representation('Int');

    # PadAccess for the LHS of Assign (the target slot)
    my $lhs  = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vd]);
    $lhs->set_representation('Int');

    # Assign: inputs[0] = lhs PadAccess (target), inputs[1] = new value
    my $asgn = $f->make('Assign', inputs => [$lhs, $c2]);
    $asgn->set_representation('Int');
    # Wire Assign into the control chain: Assign.control_in = VarDecl
    $asgn->set_control_in($vd);

    # The PadAccess that Return reads (after the Assign)
    my $pad  = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vd]);
    $pad->set_representation('Int');

    # Return's control_in = Assign (Return comes after Assign in the control chain)
    my $ret  = $f->make_cfg('Return', inputs => [$pad]);
    $ret->set_control_in($asgn);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'VAR-2 (C1): my $x=1; $x=2; return $x — lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'VAR-2 (C1): .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'VAR-2 (C1): lli exits 0');
        is($out, 'Int:2', "VAR-2 (C1): lli output 'Int:2' matches perl oracle (type-tagged)");
    }
}

# VAR-3 (C2): my $x = 1; $x += 2; return $x
# CompoundAssign(+=): reads current value of $x, adds 2, stores result back.
{
    my $f = Chalk::IR::NodeFactory->new;

    my $c1   = int_const($f, 1);
    my $c2   = int_const($f, 2);
    my $vd   = $f->make('VarDecl', inputs => [
        $f->make('Constant', value => 'x', const_type => 'string'),
        $c1
    ]);
    $vd->set_representation('Int');

    # PadAccess for reading current $x (the read side of +=)
    my $read_pad = $f->make('PadAccess', targ => 0, varname => '$x_read', inputs => [$vd]);
    $read_pad->set_representation('Int');

    # The Add node for $x + 2
    my $added = $f->make('Add', inputs => [$read_pad, $c2]);
    $added->set_representation('Int');

    # PadAccess for the LHS of the CompoundAssign (the target slot)
    my $lhs_pad = $f->make('PadAccess', targ => 0, varname => '$x_lhs', inputs => [$vd]);
    $lhs_pad->set_representation('Int');

    # CompoundAssign: inputs[0] = lhs (target slot), inputs[1] = computed value
    my $ca = $f->make('CompoundAssign', op => '+=', inputs => [$lhs_pad, $added]);
    $ca->set_representation('Int');
    $ca->set_control_in($vd);

    # PadAccess for return (after compound assign)
    my $ret_pad = $f->make('PadAccess', targ => 0, varname => '$x_ret', inputs => [$vd]);
    $ret_pad->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$ret_pad]);
    $ret->set_control_in($ca);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'VAR-3 (C2): my $x=1; $x+=2; return $x — lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'VAR-3 (C2): .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'VAR-3 (C2): lli exits 0');
        is($out, 'Int:3', "VAR-3 (C2): lli output 'Int:3' matches perl oracle (type-tagged)");
    }
}

# ===========================================================================
# GROUP 4: Comparison operators + TernaryExpr (D6 — select-based ternary)
#
# Numeric comparisons (>, <, ==, !=, >=, <=) lower to LLVM icmp instructions
# which produce i1. These are used as conditions for select (ternary) and
# later for branch instructions.
#
# TernaryExpr ($cond ? $true : $false) with Int branches and i1 condition:
# lowers to `select i1 %cond, i64 %true, i64 %false`.
#
# This does NOT require Phi nodes — `select` is a pure value instruction.
# It covers D6 from the gap-map.
# ===========================================================================

# CMP-1: NumGt(5, 3) should lower to icmp sgt i64 5, 3 → i1
{
    my $f    = Chalk::IR::NodeFactory->new;
    my $c5   = int_const($f, 5);
    my $c3   = int_const($f, 3);
    my $cmp  = $f->make('NumGt', inputs => [$c5, $c3]);
    $cmp->set_representation('Bool');   # comparison result = i1

    # Wrap in a TernaryExpr to make it returnable as an Int
    my $c1   = int_const($f, 1);
    my $c0   = int_const($f, 0);
    my $tern = $f->make('TernaryExpr', inputs => [$cmp, $c1, $c0]);
    $tern->set_representation('Int');

    my $ret  = $f->make_cfg('Return', inputs => [$tern]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'CMP-1: TernaryExpr(NumGt(5,3), 1, 0) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        like($ll, qr/icmp sgt i64/, 'CMP-1: .ll contains icmp sgt i64');
        like($ll, qr/select i1/, 'CMP-1: .ll contains select i1');
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'CMP-1: .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'CMP-1: lli exits 0');
        is($out, 'Int:1', "CMP-1: lli output 'Int:1' (5 > 3 ? 1 : 0 == 1, type-tagged)");
    }
}

# CMP-2: NumGt(1, 3) — false branch
{
    my $f    = Chalk::IR::NodeFactory->new;
    my $c1c  = int_const($f, 1);
    my $c3   = int_const($f, 3);
    my $cmp  = $f->make('NumGt', inputs => [$c1c, $c3]);
    $cmp->set_representation('Bool');

    my $c1   = int_const($f, 1);
    my $c0   = int_const($f, 0);
    my $tern = $f->make('TernaryExpr', inputs => [$cmp, $c1, $c0]);
    $tern->set_representation('Int');

    my $ret  = $f->make_cfg('Return', inputs => [$tern]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'CMP-2: TernaryExpr(NumGt(1,3), 1, 0) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 2 unless defined $ll;
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'CMP-2: lli exits 0');
        is($out, 'Int:0', "CMP-2: lli output 'Int:0' (1 > 3 ? 1 : 0 == 0, type-tagged)");
    }
}

# CMP-3 (D6 ternary idiom): return $n > 0 ? 1 : 2
# With $n as an Int constant (5), oracle = 1 (since 5 > 0 is true)
{
    my $f    = Chalk::IR::NodeFactory->new;
    my $n    = int_const($f, 5);    # $n = 5 (an Int constant representing the parameter)
    my $zero = int_const($f, 0);
    my $cmp  = $f->make('NumGt', inputs => [$n, $zero]);
    $cmp->set_representation('Bool');

    my $c1   = int_const($f, 1);
    my $c2   = int_const($f, 2);
    my $tern = $f->make('TernaryExpr', inputs => [$cmp, $c1, $c2]);
    $tern->set_representation('Int');

    my $ret  = $f->make_cfg('Return', inputs => [$tern]);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'CMP-3 (D6): return 5 > 0 ? 1 : 2 lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'CMP-3 (D6): .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'CMP-3 (D6): lli exits 0');
        is($out, 'Int:1', "CMP-3 (D6): lli output 'Int:1' (5>0 ? 1 : 2 == 1, type-tagged)");
    }
}

# ===========================================================================
# B1 SOUNDNESS: my $x=1; my $y=$x; $x=2; return $x + $y  (perl = 3)
#
# The pre-assign read ($y=$x) and post-assign read (return $x+$y) hash-cons
# to the SAME PadAccess node. The scoped-elaboration var_table+phi model
# reads var_table[vd_id] at each PadAccess lowering point, so the Return
# read sees x=2 (the post-assign value) rather than the stale x=1. This
# supersedes the original "B1 poison guard" (introduced in the 3c gate
# review), which died with a GAP when it saw a cached pre-assign read being
# re-read. The new model is program-point-correct: no stale cache exists
# for PadAccess nodes because they always read the current var_table entry.
# See t/bootstrap/ir/llvm-reassign-soundness.t for the full adversarial
# proof covering straight-line, branch, and loop shapes.
# ===========================================================================
{
    my $f  = Chalk::IR::NodeFactory->new;
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    my $c1 = int_const($f, 1);
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]); $vx->set_representation('Int');

    # my $y = $x;  (pre-assign read of $x — x=1)
    my $rx1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx1->set_representation('Int');
    my $ny  = $f->make('Constant', value => '$y', const_type => 'string');
    my $vy  = $f->make('VarDecl', inputs => [$ny, $rx1]); $vy->set_representation('Int');

    # $x = 2;  (reassignment — updates var_table[vx] to new SSA value)
    my $c2  = int_const($f, 2);
    my $rxL = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rxL->set_representation('Int');
    my $asg = $f->make('Assign', inputs => [$rxL, $c2]); $asg->set_representation('Int');

    # return $x + $y;  ($x and $rxL and $rx1 are all the same hash-consed node;
    # the scoped model reads var_table[vx] which now holds x=2)
    my $rx2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx2->set_representation('Int');
    my $ryF = $f->make('PadAccess', targ => 0, varname => '$y', inputs => [$vy]);
    $ryF->set_representation('Int');
    my $add = $f->make('Add', inputs => [$rx2, $ryF]); $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);
    $ret->set_control_in($asg); $asg->set_control_in($vy); $vy->set_control_in($vx);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'B1: read-before-and-after-reassign lowers correctly (scoped var_table is program-point-aware)')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'B1: .ll is libperl-free');

        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'B1: lli exits 0');
        is($out, 'Int:3',
            'B1: lli=Int:3 == perl=Int:3 (x=2 post-assign, y=1 pre-assign, 2+1=3, type-tagged)');
    }
}

done_testing;
