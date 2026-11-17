# ABOUTME: A value with no stamp is never guessed as Int: T2 refuses it by name where it cannot
# ABOUTME: type it, and types it from its operands where it can (two Ints' Add) -- never i64 by default.
use 5.42.0;
use utf8;

use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::Rooted qw(rooted);

# printed($f, $value) -> a Return after a Print of $value: a value the program
# never reads is no part of what T2 builds, so each fixture prints its value.
sub printed ($f, $v) {
    my $p = $f->make('Print', inputs => [$v]);
    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_stamp('Undef');
    my $r = $f->make_cfg('Return', inputs => [$u]);
    $r->set_control_in($p);
    return rooted($r);
}

# G.6 (F7): ~19 sites use `my $repr = $node->stamp // 'Int'`.
# An undef-repr node is silently lowered as i64 BEFORE the `repr eq 'Scalar' -> die`
# check runs; _lower_constant emits `add i64 0, $val` for an undef-repr Constant.
# This masks upstream type-inference bugs as plausible integer output.
#
# Fix: replace `// 'Int'` defaulting with an explicit loud die:
#   "node <op> has no representation at lowering time (GAP: fix TypeInference)"
# Consistent with _ensure_i1 which already dies on undef-repr.

# Test 1: undef-repr Constant must die loudly, not emit 'add i64 0, ...'
subtest 'undef-repr Constant dies loudly instead of silently lowering as Int' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => 42, const_type => 'integer');
    # Intentionally do NOT set representation — simulates a TypeInference gap.
    my $ret = printed($f, $c);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    # After G.6: lower() must die (loud GAP).
    # Before G.6: lower() SUCCEEDS and emits 'add i64 0, 42' silently.
    ok(defined $err && length $err,
        'undef-repr Constant: lower() dies loudly')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 300));

    if (defined $err) {
        like($err, qr/representation|repr|GAP/i,
            'error message mentions representation or GAP')
            or diag("error: $err");
    }
};

# Test 2: undef-repr Add dies loudly
subtest 'an unstamped Add of two Ints is typed from its operands' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $a = $f->make('Constant', value => 3, const_type => 'integer');
    $a->set_stamp('Int');
    my $b = $f->make('Constant', value => 4, const_type => 'integer');
    $b->set_stamp('Int');
    my $add = $f->make('Add', inputs => [$a, $b]);
    # Intentionally do NOT set representation on Add.
    my $ret = printed($f, $add);

    # T2 TYPES IT FROM ITS OPERANDS (two Ints), not from a stamp: no guess to
    # make, and the module prints perl's answer.
    my $ll = eval { Chalk::Target::LLVM->lower($ret) };
    ok(defined $ll, 'an unstamped Add: T2 lowers it') or diag $@;
    my $lli = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
    SKIP: {
        skip "no lli at $lli", 1 unless -x $lli && defined $ll;
        require File::Temp;
        my ($fh, $path) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $fh $ll; close $fh;
        is(scalar qx($lli $path 2>&1), '7', 'an unstamped Add: prints perl\'s 7');
    }
};

# Test 3: a well-typed graph (all nodes have representation) still lowers correctly.
subtest 'well-typed graph with explicit repr still lowers correctly' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => 7, const_type => 'integer');
    $c->set_stamp('Int');
    my $ret = printed($f, $c);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(!defined $err || !length $err,
        'well-typed Constant: lower() does not die')
        or diag("Unexpected error: $err");
    ok(defined $ll && length $ll,
        'well-typed Constant: lower() returns .ll text');
};

# ============================================================
# G.6 extension: representative control-flow families across the 19 sites.
# Each subtest proves that site N silently emits i64 before the fix (RED)
# and dies loudly after the fix (GREEN).
# ============================================================

# Test 4: undef-repr VarDecl dies loudly (site: line ~1753, _lower_vardecl)
subtest 'undef-repr VarDecl dies loudly instead of silently lowering as Int' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    # Build: my $x = 1; return $x
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    $nx->set_stamp('Str');
    my $c1 = $f->make('Constant', value => 1, const_type => 'integer');
    $c1->set_stamp('Int');
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]);
    # Intentionally do NOT set representation on vx — this is the gap.
    my $rx = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'x', inputs => [$vx]);
    $rx->set_stamp('Int');
    my $ret = printed($f, $rx);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'undef-repr VarDecl: lower() dies loudly')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 300));
    if (defined $err && length $err) {
        like($err, qr/representation|repr|GAP/i,
            'VarDecl error message mentions representation or GAP')
            or diag("error: $err");
    }
};

# Test 5: undef-repr PadAccess dies loudly (site: line ~1806, _lower_padaccess)
subtest 'undef-repr PadAccess dies loudly instead of silently lowering as Int' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    $nx->set_stamp('Str');
    my $c1 = $f->make('Constant', value => 1, const_type => 'integer');
    $c1->set_stamp('Int');
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]);
    $vx->set_stamp('Int');
    my $rx = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'x', inputs => [$vx]);
    # Intentionally do NOT set representation on PadAccess.
    my $ret = printed($f, $rx);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'undef-repr PadAccess: lower() dies loudly')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 300));
    if (defined $err && length $err) {
        like($err, qr/representation|repr|GAP/i,
            'PadAccess error message mentions representation or GAP')
            or diag("error: $err");
    }
};

# Test 6: undef-repr Assign dies loudly (site: line ~1859, _lower_assign)
subtest 'undef-repr Assign dies loudly instead of silently lowering as Int' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    $nx->set_stamp('Str');
    my $c1 = $f->make('Constant', value => 1, const_type => 'integer');
    $c1->set_stamp('Int');
    my $c2 = $f->make('Constant', value => 2, const_type => 'integer');
    $c2->set_stamp('Int');
    my $vx  = $f->make('VarDecl', inputs => [$nx, $c1]);
    $vx->set_stamp('Int');
    my $rxL = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'x', inputs => [$vx]);
    $rxL->set_stamp('Int');
    my $asg = $f->make('Assign', inputs => [$rxL, $c2]);
    # Intentionally do NOT set representation on Assign.
    my $ret = printed($f, $asg);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'undef-repr Assign: lower() dies loudly')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 300));
    if (defined $err && length $err) {
        like($err, qr/representation|repr|GAP/i,
            'Assign error message mentions representation or GAP')
            or diag("error: $err");
    }
};

# Test 7: undef-repr TernaryExpr branch dies loudly (sites: lines ~1963/1964)
# CG3 fix: prior version used Constant(:Boolean) as cond, which dies at constant-lowering
# ("cannot lower Constant with repr=Boolean"), BEFORE the TernaryExpr guard fires.
# Fixed: use Constant(:Int) as cond so the TernaryExpr guard is the actual die site.
subtest 'undef-repr TernaryExpr true-branch dies loudly' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    # Condition: Int is valid (truthiness check via icmp ne i64 %v, 0)
    my $cond = $f->make('Constant', value => 1, const_type => 'integer');
    $cond->set_stamp('Int');
    my $true_c = $f->make('Constant', value => 10, const_type => 'integer');
    # Intentionally do NOT set representation on true branch — this is the guard site.
    my $fals_c = $f->make('Constant', value => 20, const_type => 'integer');
    $fals_c->set_stamp('Int');
    my $tern = $f->make('TernaryExpr', inputs => [$cond, $true_c, $fals_c]);
    $tern->set_stamp('Int');
    my $ret = printed($f, $tern);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'undef-repr TernaryExpr true-branch: lower() dies loudly (at TernaryExpr guard, not Constant lowering)')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 300));
    if (defined $err && length $err) {
        like($err, qr/representation|repr|GAP/i,
            'TernaryExpr error message mentions representation or GAP')
            or diag("error: $err");
        # The error must come from the TernaryExpr guard, not the Constant :Boolean path.
        unlike($err, qr/cannot lower Constant with repr=Boolean/i,
            'TernaryExpr error is NOT the old Constant-repr=Boolean die (CG3: guard fires correctly)')
            or diag("Error came from wrong guard: Constant repr=Boolean die, not TernaryExpr guard\nerror: $err");
    }
};


# Test 8: undef-repr DefinedOr lhs dies loudly (site: line ~2163, _lower_defined_or)
subtest 'undef-repr DefinedOr lhs dies loudly' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => 5, const_type => 'integer');
    # Intentionally do NOT set representation on lhs.
    my $rhs = $f->make('Constant', value => 99, const_type => 'integer');
    $rhs->set_stamp('Int');
    my $dor = $f->make('DefinedOr', inputs => [$lhs, $rhs]);
    $dor->set_stamp('Int');
    my $ret = printed($f, $dor);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'undef-repr DefinedOr lhs: lower() dies loudly')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 300));
    if (defined $err && length $err) {
        like($err, qr/representation|repr|GAP/i,
            'DefinedOr error message mentions representation or GAP')
            or diag("error: $err");
    }
};

# ============================================================
# Phase 3 step 5 (B4/D3): the four remaining backend `// 'Int'` guesses in
# Context.pm become loud GAPs. The 2026-08-27 census found no LIVE guess at any
# of them -- every reaching case has a DEFINED left operand -- but the reaching
# values are NOT uniformly Int (the vtable ABI site sees Str and Undef), so an
# undef arrival would have emitted an i64 cast over a string. Per spec §1 a
# silent guess is the only unacceptable outcome; a GAP is fine.
# ============================================================


# Site A (_lower_defined_or, the phi-repr read): the DefinedOr NODE's own repr.
# Test 8 above covers the LHS; this covers the node. `$repr` is read TWICE in
# one ternary, so the fix hoists a single required fetch above the expression.
subtest 'an unstamped DefinedOr of two Ints is typed from its operands' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => 5, const_type => 'integer');
    $lhs->set_stamp('Int');
    my $rhs = $f->make('Constant', value => 99, const_type => 'integer');
    $rhs->set_stamp('Int');
    my $dor = $f->make('DefinedOr', inputs => [$lhs, $rhs]);
    # Intentionally do NOT set representation on the DefinedOr itself.
    my $ret = printed($f, $dor);

    # T2 TYPES IT FROM ITS OPERANDS (two Ints), not from a stamp: no guess to
    # make, and the module prints perl's answer.
    my $ll = eval { Chalk::Target::LLVM->lower($ret) };
    ok(defined $ll, 'an unstamped DefinedOr: T2 lowers it') or diag $@;
    my $lli = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
    SKIP: {
        skip "no lli at $lli", 1 unless -x $lli && defined $ll;
        require File::Temp;
        my ($fh, $path) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $fh $ll; close $fh;
        is(scalar qx($lli $path 2>&1), '5', 'an unstamped DefinedOr: prints perl\'s 5');
    }
};


done_testing();
