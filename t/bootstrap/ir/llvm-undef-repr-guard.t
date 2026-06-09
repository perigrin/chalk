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

done_testing();
