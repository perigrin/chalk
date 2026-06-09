# ABOUTME: G.7 gate-hardening: And/Or/Not must die loudly on non-Int operands.
# ABOUTME: Verifies that Bool operands to && / || produce a loud GAP not a silent i64 misread.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

# G.7 (F8): _lower_and/_lower_or hardcode `icmp ne i64` for truthiness,
# assuming Int operands. A Bool(i1) operand would be silently reinterpreted
# as i64 (zero-extended), which could produce wrong results.
#
# Fix (per plan, C2): keep `icmp ne i64` for Int operands but DIE LOUDLY on
# a non-Int operand ("&&/||/! operand has repr X; only Int truthiness is
# lowered runtime-free — GAP").
#
# The L1/L2 cases (Int operands) must stay GREEN with no corpus change.
# An And(Bool,Bool) graph must GAP loudly.

my $LLI = '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Build a Bool-valued node: Constant(5 :Int) -> Coerce(Int->Bool) :Bool
sub make_bool_node {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => $val, const_type => 'integer');
    $c->set_representation('Int');
    my $coerce = $f->make('Coerce', inputs => [$c], from_repr => 'Int', to_repr => 'Bool');
    $coerce->set_representation('Bool');
    return $coerce;
}

# Test 1: And(Int, Int) — must still work (L1/L2 stay GREEN)
subtest 'And(Int, Int) still lowers correctly (L1 regression guard)' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $a = $f->make('Constant', value => 3, const_type => 'integer');
    $a->set_representation('Int');
    my $b = $f->make('Constant', value => 7, const_type => 'integer');
    $b->set_representation('Int');
    my $and = $f->make('And', inputs => [$a, $b]);
    $and->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$and]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(!defined $err || !length $err, 'And(Int,Int): lower() does not die')
        or diag("error: $err");
    ok($ll =~ /icmp ne i64/, 'And(Int,Int): .ll contains Int truthiness check')
        if !$err;
};

# Test 2: Or(Int, Int) — must still work (L2 regression guard)
subtest 'Or(Int, Int) still lowers correctly (L2 regression guard)' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $a = $f->make('Constant', value => 3, const_type => 'integer');
    $a->set_representation('Int');
    my $b = $f->make('Constant', value => 7, const_type => 'integer');
    $b->set_representation('Int');
    my $or = $f->make('Or', inputs => [$a, $b]);
    $or->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$or]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(!defined $err || !length $err, 'Or(Int,Int): lower() does not die')
        or diag("error: $err");
};

# Test 3: And(Bool, Bool) — must GAP loudly (not silently reinterpret i1 as i64)
subtest 'And(Bool, Bool) GAPs loudly — not a silent i64 misread' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $a = make_bool_node($f, 1);   # Bool: true
    my $b = make_bool_node($f, 0);   # Bool: false
    my $and = $f->make('And', inputs => [$a, $b]);
    $and->set_representation('Bool');
    my $ret = $f->make_cfg('Return', inputs => [$and]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    # After G.7: must die loudly with a repr/GAP message.
    # Before G.7: silently emits `icmp ne i64 %i1_val, 0` — type-mismatched.
    ok(defined $err && length $err,
        'And(Bool,Bool): lower() dies loudly on non-Int LHS operand')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 200));

    if (defined $err) {
        like($err, qr/repr|representation|GAP|Bool|truthiness/i,
            'error mentions repr/Bool/GAP')
            or diag("error: $err");
    }
};

# Test 4: Or(Bool, Bool) — must also GAP loudly
subtest 'Or(Bool, Bool) GAPs loudly on non-Int operand' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $a = make_bool_node($f, 5);   # Bool: true (5 is truthy)
    my $b = make_bool_node($f, 0);   # Bool: false
    my $or = $f->make('Or', inputs => [$a, $b]);
    $or->set_representation('Bool');
    my $ret = $f->make_cfg('Return', inputs => [$or]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'Or(Bool,Bool): lower() dies loudly on non-Int LHS operand')
        or diag("Got no error; .ll:\n" . substr($ll // '', 0, 200));
};

# I2 (R1 reopened): RHS guard missing — And/Or(Int, non-Int) must GAP loudly.
# Before I2 fix: LHS guard passes (Int), RHS lowered silently with wrong type,
# phi merges i64 with i1/double = invalid LLVM (miscompile or lli-reject).
# After I2 fix: RHS repr checked identically to LHS; non-Int RHS dies loudly.

# Build a Num-valued node: Constant(3.14 :Num)
sub make_num_node {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => $val, const_type => 'float');
    $c->set_representation('Num');
    return $c;
}

# Test 5: And(Int, Bool) — Int LHS passes guard, Bool RHS must GAP loudly
subtest 'And(Int, Bool) GAPs loudly on non-Int RHS operand (I2)' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => 5, const_type => 'integer');
    $lhs->set_representation('Int');
    my $rhs = make_bool_node($f, 1);   # Bool
    my $and = $f->make('And', inputs => [$lhs, $rhs]);
    $and->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$and]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'And(Int,Bool): lower() dies loudly on non-Int RHS operand (I2)')
        or diag("Got no error — RHS guard is missing; .ll:\n" . substr($ll // '', 0, 300));

    if (defined $err) {
        like($err, qr/repr|representation|GAP|Bool|RHS/i,
            'error mentions repr/Bool/GAP/RHS')
            or diag("error: $err");
    }
};

# Test 6: And(Int, Num) — Int LHS passes guard, Num RHS must GAP loudly
subtest 'And(Int, Num) GAPs loudly on non-Int RHS operand (I2)' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => 5, const_type => 'integer');
    $lhs->set_representation('Int');
    my $rhs = make_num_node($f, 3.14);
    my $and = $f->make('And', inputs => [$lhs, $rhs]);
    $and->set_representation('Num');
    my $ret = $f->make_cfg('Return', inputs => [$and]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'And(Int,Num): lower() dies loudly on non-Int RHS operand (I2)')
        or diag("Got no error — RHS guard is missing; .ll:\n" . substr($ll // '', 0, 300));

    if (defined $err) {
        like($err, qr/repr|representation|GAP|Num|RHS/i,
            'error mentions repr/Num/GAP/RHS')
            or diag("error: $err");
    }
};

# Test 7: Or(Int, Bool) — must GAP loudly on non-Int RHS
subtest 'Or(Int, Bool) GAPs loudly on non-Int RHS operand (I2)' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => 0, const_type => 'integer');
    $lhs->set_representation('Int');
    my $rhs = make_bool_node($f, 1);   # Bool
    my $or = $f->make('Or', inputs => [$lhs, $rhs]);
    $or->set_representation('Bool');
    my $ret = $f->make_cfg('Return', inputs => [$or]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'Or(Int,Bool): lower() dies loudly on non-Int RHS operand (I2)')
        or diag("Got no error — RHS guard is missing; .ll:\n" . substr($ll // '', 0, 300));
};

# Test 8: Or(Int, Num) — must GAP loudly on non-Int RHS
subtest 'Or(Int, Num) GAPs loudly on non-Int RHS operand (I2)' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $lhs = $f->make('Constant', value => 0, const_type => 'integer');
    $lhs->set_representation('Int');
    my $rhs = make_num_node($f, 2.718);
    my $or = $f->make('Or', inputs => [$lhs, $rhs]);
    $or->set_representation('Num');
    my $ret = $f->make_cfg('Return', inputs => [$or]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(defined $err && length $err,
        'Or(Int,Num): lower() dies loudly on non-Int RHS operand (I2)')
        or diag("Got no error — RHS guard is missing; .ll:\n" . substr($ll // '', 0, 300));
};

done_testing();
