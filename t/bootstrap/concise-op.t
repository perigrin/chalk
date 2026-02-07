# ABOUTME: Tests for ConciseOp data class representing a single B::Concise operation.
# ABOUTME: Covers construction, field access, to_string rendering, and structural_key generation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::ConciseOp;

# --- Construction with all fields ---
{
    my $op = Chalk::Bootstrap::ConciseOp->new(
        name      => 'padsv_store',
        arity     => '2',
        type_info => '$x',
        flags     => 'sM/LVINTRO',
        private   => '/LVINTRO',
    );

    is($op->name(), 'padsv_store', 'name field');
    is($op->arity(), '2', 'arity field');
    is($op->type_info(), '$x', 'type_info field');
    is($op->flags(), 'sM/LVINTRO', 'flags field');
    is($op->private(), '/LVINTRO', 'private field');
}

# --- Construction with defaults ---
{
    my $op = Chalk::Bootstrap::ConciseOp->new(
        name  => 'enter',
        arity => '0',
    );

    is($op->name(), 'enter', 'minimal construction name');
    is($op->arity(), '0', 'minimal construction arity');
    is($op->type_info(), undef, 'type_info defaults to undef');
    is($op->flags(), '', 'flags defaults to empty string');
    is($op->private(), '', 'private defaults to empty string');
}

# --- Construction with type_info variants ---
{
    my $iv_op = Chalk::Bootstrap::ConciseOp->new(
        name      => 'const',
        arity     => '$',
        type_info => 'IV 42',
    );
    is($iv_op->type_info(), 'IV 42', 'IV type_info');

    my $pv_op = Chalk::Bootstrap::ConciseOp->new(
        name      => 'const',
        arity     => '$',
        type_info => 'PV "hello"',
    );
    is($pv_op->type_info(), 'PV "hello"', 'PV type_info');

    my $nv_op = Chalk::Bootstrap::ConciseOp->new(
        name      => 'const',
        arity     => '$',
        type_info => 'NV 3.14',
    );
    is($nv_op->type_info(), 'NV 3.14', 'NV type_info');
}

# --- to_string rendering ---
{
    my $op = Chalk::Bootstrap::ConciseOp->new(
        name  => 'enter',
        arity => '0',
    );
    like($op->to_string(), qr/enter/, 'to_string contains op name');
    like($op->to_string(), qr/<0>/, 'to_string contains arity marker');

    my $const_op = Chalk::Bootstrap::ConciseOp->new(
        name      => 'const',
        arity     => '$',
        type_info => 'IV 42',
    );
    like($const_op->to_string(), qr/const/, 'to_string for const contains name');
    like($const_op->to_string(), qr/IV 42/, 'to_string for const contains type_info');

    my $padsv_op = Chalk::Bootstrap::ConciseOp->new(
        name      => 'padsv_store',
        arity     => '2',
        type_info => '$x',
        private   => '/LVINTRO',
    );
    like($padsv_op->to_string(), qr/padsv_store/, 'to_string for padsv_store contains name');
    like($padsv_op->to_string(), qr/\$x/, 'to_string for padsv_store contains var name');
    like($padsv_op->to_string(), qr{/LVINTRO}, 'to_string for padsv_store contains private flags');
}

# --- structural_key generation ---
{
    # structural_key should produce a normalized key for comparison
    my $op1 = Chalk::Bootstrap::ConciseOp->new(
        name  => 'enter',
        arity => '0',
    );
    my $key1 = $op1->structural_key();
    ok(defined $key1, 'structural_key returns defined value');
    like($key1, qr/enter/, 'structural_key contains op name');

    # Same op name/arity/type should produce same key
    my $op2 = Chalk::Bootstrap::ConciseOp->new(
        name  => 'enter',
        arity => '0',
        flags => 'different_flags',
    );
    is($op1->structural_key(), $op2->structural_key(),
        'structural_key ignores flags');

    # Different names produce different keys
    my $op3 = Chalk::Bootstrap::ConciseOp->new(
        name  => 'leave',
        arity => '@',
    );
    isnt($op1->structural_key(), $op3->structural_key(),
        'different op names produce different keys');

    # const ops include type in structural_key
    my $iv = Chalk::Bootstrap::ConciseOp->new(
        name      => 'const',
        arity     => '$',
        type_info => 'IV 42',
    );
    my $pv = Chalk::Bootstrap::ConciseOp->new(
        name      => 'const',
        arity     => '$',
        type_info => 'PV "hello"',
    );
    isnt($iv->structural_key(), $pv->structural_key(),
        'const IV and const PV have different structural keys');

    # Variable ops include sigil in structural_key
    my $padsv = Chalk::Bootstrap::ConciseOp->new(
        name      => 'padsv_store',
        arity     => '2',
        type_info => '$x',
        private   => '/LVINTRO',
    );
    like($padsv->structural_key(), qr/padsv_store/,
        'variable op structural_key includes op name');

    # Private flags like /LVINTRO ARE significant for structural comparison
    my $no_intro = Chalk::Bootstrap::ConciseOp->new(
        name      => 'padsv',
        arity     => '1',
        type_info => '$x',
    );
    my $with_intro = Chalk::Bootstrap::ConciseOp->new(
        name      => 'padsv',
        arity     => '1',
        type_info => '$x',
        private   => '/LVINTRO',
    );
    isnt($no_intro->structural_key(), $with_intro->structural_key(),
        'private flags affect structural_key');
}

done_testing;
