# ABOUTME: Assign over a Subscript/FieldAccess lvalue is a side-effecting store and
# ABOUTME: must have per-call identity — two identical stores must NOT hash-cons to one.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;

# A store statement (element/field write) carries a control position: two
# textually-identical stores in sequence are DISTINCT side effects. The old
# FieldWrite/element-write nodes had per-call identity; the converged
# Assign(lvalue, value) form must preserve it, or one of two identical adjacent
# stores is silently dropped by hash-consing (control_in is excluded from the
# content hash).

subtest 'Assign(FieldAccess-lvalue) has per-call identity' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $mk_store = sub {
        my $fa = $f->make('FieldAccess', field_index => 0, field_stash => 'Counter', inputs => []);
        $fa->set_representation('Int');
        my $v = $f->make('Constant', value => '7', const_type => 'integer');
        $v->set_representation('Int');
        my $a = $f->make('Assign', inputs => [$fa, $v]);
        $a->set_representation('Int');
        return $a;
    };

    my $s1 = $mk_store->();
    my $s2 = $mk_store->();

    isnt($s1->id, $s2->id,
        'two identical Assign(FieldAccess-lvalue, 7) are distinct nodes (not hash-consed)');
};

subtest 'Assign(Subscript-lvalue) has per-call identity' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $mk_store = sub {
        my $arr = $f->make('ArrayRef', inputs => []);
        $arr->set_representation('ArrayRef');
        my $idx = $f->make('Constant', value => '0', const_type => 'integer');
        $idx->set_representation('Int');
        my $sub = $f->make('Subscript', inputs => [$arr, $idx]);
        $sub->set_representation('Int');
        my $v = $f->make('Constant', value => '42', const_type => 'integer');
        $v->set_representation('Int');
        my $a = $f->make('Assign', inputs => [$sub, $v]);
        $a->set_representation('Int');
        return $a;
    };

    my $s1 = $mk_store->();
    my $s2 = $mk_store->();

    isnt($s1->id, $s2->id,
        'two identical Assign(Subscript-lvalue, 42) are distinct nodes (not hash-consed)');
};

subtest 'Assign with a non-lvalue lhs (scalar rebind) still hash-conses by content' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # An Assign whose lhs is a plain PadAccess (scalar rebind, value-producing)
    # is NOT a store-to-aggregate; it should keep ordinary content hash-consing.
    # Use SHARED lhs/rhs nodes so the two Assigns are genuinely content-identical
    # (a fresh VarDecl per build would differ by VarDecl#N and miss the point).
    my $vd = $f->make('VarDecl',
        inputs => [
            $f->make('Constant', value => 'x', const_type => 'string'),
            $f->make('Constant', value => '1', const_type => 'integer'),
        ]);
    my $pa = $f->make('PadAccess', targ => 0, varname => 'x', inputs => [$vd]);
    $pa->set_representation('Int');
    my $v = $f->make('Constant', value => '9', const_type => 'integer');
    $v->set_representation('Int');

    my $r1 = $f->make('Assign', inputs => [$pa, $v]);
    my $r2 = $f->make('Assign', inputs => [$pa, $v]);

    is($r1->id, $r2->id,
        'two identical scalar-rebind Assigns DO hash-cons (no aggregate store)');
};

done_testing;
