# ABOUTME: G.6 gate-hardening: undef-repr nodes must GAP loudly, not silently lower as Int.
# ABOUTME: Verifies that nodes with no representation set die rather than silently emit i64.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

# G.6 (F7): ~19 sites use `my $repr = $node->representation // 'Int'`.
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
    my $ret = $f->make_cfg('Return', inputs => [$c]);

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
subtest 'undef-repr Add node dies loudly instead of silently lowering as i64' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $a = $f->make('Constant', value => 3, const_type => 'integer');
    $a->set_representation('Int');
    my $b = $f->make('Constant', value => 4, const_type => 'integer');
    $b->set_representation('Int');
    my $add = $f->make('Add', inputs => [$a, $b]);
    # Intentionally do NOT set representation on Add.
    my $ret = $f->make_cfg('Return', inputs => [$add]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'undef-repr Add node: lower() dies loudly')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 300));

    if (defined $err) {
        like($err, qr/representation|repr|GAP/i,
            'error message mentions representation or GAP')
            or diag("error: $err");
    }
};

# Test 3: a well-typed graph (all nodes have representation) still lowers correctly.
subtest 'well-typed graph with explicit repr still lowers correctly' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $c = $f->make('Constant', value => 7, const_type => 'integer');
    $c->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$c]);

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
    $nx->set_representation('Str');
    my $c1 = $f->make('Constant', value => 1, const_type => 'integer');
    $c1->set_representation('Int');
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]);
    # Intentionally do NOT set representation on vx — this is the gap.
    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$rx]);

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
    $nx->set_representation('Str');
    my $c1 = $f->make('Constant', value => 1, const_type => 'integer');
    $c1->set_representation('Int');
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]);
    $vx->set_representation('Int');
    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    # Intentionally do NOT set representation on PadAccess.
    my $ret = $f->make_cfg('Return', inputs => [$rx]);

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
    $nx->set_representation('Str');
    my $c1 = $f->make('Constant', value => 1, const_type => 'integer');
    $c1->set_representation('Int');
    my $c2 = $f->make('Constant', value => 2, const_type => 'integer');
    $c2->set_representation('Int');
    my $vx  = $f->make('VarDecl', inputs => [$nx, $c1]);
    $vx->set_representation('Int');
    my $rxL = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rxL->set_representation('Int');
    my $asg = $f->make('Assign', inputs => [$rxL, $c2]);
    # Intentionally do NOT set representation on Assign.
    my $ret = $f->make_cfg('Return', inputs => [$asg]);

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
subtest 'undef-repr TernaryExpr true-branch dies loudly' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $cond = $f->make('Constant', value => 1, const_type => 'integer');
    $cond->set_representation('Bool');
    my $true_c = $f->make('Constant', value => 10, const_type => 'integer');
    # Intentionally do NOT set representation on true branch.
    my $fals_c = $f->make('Constant', value => 20, const_type => 'integer');
    $fals_c->set_representation('Int');
    my $tern = $f->make('TernaryExpr', inputs => [$cond, $true_c, $fals_c]);
    $tern->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$tern]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'undef-repr TernaryExpr true-branch: lower() dies loudly')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 300));
    if (defined $err && length $err) {
        like($err, qr/representation|repr|GAP/i,
            'TernaryExpr error message mentions representation or GAP')
            or diag("error: $err");
    }
};

# Test 8: undef-repr DefinedOr lhs dies loudly (site: line ~2163, _lower_defined_or)
subtest 'undef-repr DefinedOr lhs dies loudly' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => 5, const_type => 'integer');
    # Intentionally do NOT set representation on lhs.
    my $rhs = $f->make('Constant', value => 99, const_type => 'integer');
    $rhs->set_representation('Int');
    my $dor = $f->make('DefinedOr', inputs => [$lhs, $rhs]);
    $dor->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$dor]);

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

done_testing();
