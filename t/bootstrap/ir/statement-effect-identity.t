# ABOUTME: Statement-effect ops (Assign/CompoundAssign/RegexSubst/TryCatch/Call) have
# ABOUTME: per-call identity; pure data ops hash-cons; Graph keys per-call nodes by id.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;

# A statement-effect op occupies a control position: two textually-identical
# occurrences in sequence are DISTINCT side effects (control_in is excluded
# from the content hash). Hash-consing them collapses two effects into one,
# silently dropping a store/call/substitution. The set of ops with this
# semantics is the SAME set the Block control-chain fixup threads via
# set_control_in — one table, %Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS,
# is the single source of truth for both.

subtest 'STATEMENT_EFFECT_OPS table is the shared contract' => sub {
    my %expected = map { $_ => 1 } qw(Assign CompoundAssign RegexSubst TryCatch Call);
    is_deeply(
        { map { $_ => 1 } keys %Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS },
        \%expected,
        'table contains exactly Assign/CompoundAssign/RegexSubst/TryCatch/Call');
};

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

subtest 'Assign with a scalar-rebind lhs ALSO has per-call identity' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # A scalar rebind ($x = $x + 1; $x = $x + 1;) is just as much a distinct
    # side effect per occurrence as an aggregate store. Hash-consing two
    # identical rebinds collapses them into one Assign node, and the Block
    # control-chain fixup then threads ONE node where two statements existed —
    # the second increment vanishes (probe_d_repeat_rebind: Int:2 vs perl's
    # Int:3). ALL Assigns are statement effects.
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

    isnt($r1->id, $r2->id,
        'two identical scalar-rebind Assigns are distinct nodes (not hash-consed)');
};

subtest 'CompoundAssign has per-call identity' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $vd = $f->make('VarDecl',
        inputs => [
            $f->make('Constant', value => 'x', const_type => 'string'),
            $f->make('Constant', value => '1', const_type => 'integer'),
        ]);
    my $pa = $f->make('PadAccess', targ => 0, varname => 'x', inputs => [$vd]);
    my $v  = $f->make('Constant', value => '2', const_type => 'integer');

    my $c1 = $f->make('CompoundAssign', op => '+=', inputs => [$pa, $v]);
    my $c2 = $f->make('CompoundAssign', op => '+=', inputs => [$pa, $v]);

    isnt($c1->id, $c2->id,
        'two identical $x += 2 statements are distinct nodes (not hash-consed)');
};

subtest 'RegexSubst has per-call identity' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $vd = $f->make('VarDecl',
        inputs => [
            $f->make('Constant', value => 's', const_type => 'string'),
            $f->make('Constant', value => 'aaa', const_type => 'string'),
        ]);
    my $pa = $f->make('PadAccess', targ => 0, varname => 's', inputs => [$vd]);

    my $r1 = $f->make('RegexSubst', pattern => 'a', replacement => 'b',
        flags => '', inputs => [$pa]);
    my $r2 = $f->make('RegexSubst', pattern => 'a', replacement => 'b',
        flags => '', inputs => [$pa]);

    isnt($r1->id, $r2->id,
        'two identical s/a/b/ statements are distinct nodes (not hash-consed)');
};

subtest 'TryCatch has per-call identity' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $body = $f->make('Constant', value => '1', const_type => 'integer');

    my $t1 = $f->make('TryCatch', inputs => [$body]);
    my $t2 = $f->make('TryCatch', inputs => [$body]);

    isnt($t1->id, $t2->id,
        'two identical try/catch statements are distinct nodes (not hash-consed)');
};

# Branch-review I1: pu's MethodCall node had per-call identity ("New,
# MethodCall, and FieldWrite have per-call identity"); the converged Call
# extends that to ALL dispatch kinds — any call may carry a side effect, and
# two identical statement-position calls are distinct effects.
subtest 'Call(dispatch_kind=method) has per-call identity (pu MethodCall parity)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $obj = $f->make('Constant', value => 'obj-stand-in', const_type => 'string');
    my $c1 = $f->make('Call', dispatch_kind => 'method', name => 'advance',
        inputs => [$obj]);
    my $c2 = $f->make('Call', dispatch_kind => 'method', name => 'advance',
        inputs => [$obj]);

    isnt($c1->id, $c2->id,
        'two identical method-dispatch Calls are distinct nodes (not hash-consed)');
};

subtest 'Call(dispatch_kind=builtin/sub) ALSO has per-call identity' => sub {
    # push(@a, 1); push(@a, 1); are two distinct effects. Builtin/sub calls
    # were hash-consed on pu — that is part of the statement-collapse family
    # (whole-branch review C3), not a behavior to preserve.
    my $f = Chalk::IR::NodeFactory->new;

    my $arg = $f->make('Constant', value => '1', const_type => 'integer');
    my $b1 = $f->make('Call', dispatch_kind => 'builtin', name => 'push',
        inputs => [$arg]);
    my $b2 = $f->make('Call', dispatch_kind => 'builtin', name => 'push',
        inputs => [$arg]);

    isnt($b1->id, $b2->id,
        'two identical builtin Calls are distinct nodes (not hash-consed)');
};

subtest 'pure data ops still hash-cons by content' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $c1 = $f->make('Constant', value => '5', const_type => 'integer');
    my $c2 = $f->make('Constant', value => '5', const_type => 'integer');
    is($c1->id, $c2->id, 'identical Constants hash-cons');

    my $a1 = $f->make('Add', inputs => [$c1, $c2]);
    my $a2 = $f->make('Add', inputs => [$c1, $c2]);
    is($a1->id, $a2->id, 'identical Adds hash-cons');
};

subtest 'Graph::merge keys per-call nodes by id (distinct members)' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $g = Chalk::IR::Graph->new;

    my $mk_store = sub {
        my $fa = $f->make('FieldAccess', field_index => 0, field_stash => 'Counter', inputs => []);
        my $v = $f->make('Constant', value => '7', const_type => 'integer');
        return $f->make('Assign', inputs => [$fa, $v]);
    };

    my $s1 = $mk_store->();
    my $s2 = $mk_store->();

    is($g->merge($s1)->id, $s1->id, 'merge returns the first per-call node');
    is($g->merge($s2)->id, $s2->id,
        'merge returns the SAME per-call node passed in, not a content-equal earlier member');

    my %member = map { $_->id => 1 } $g->nodes()->@*;
    ok($member{$s1->id} && $member{$s2->id},
        'both content-identical per-call nodes are graph members');
};

subtest 'Graph::nodes does not leak content-identical per-call orphans' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $g = Chalk::IR::Graph->new;

    # s1 is merged; s2 is a content-identical orphan (a losing Earley
    # alternative that was never merged). s2 is reachable via the shared
    # inputs' consumer lists. The membership filter must key per-call nodes
    # by id — a content-hash fallback would treat the orphan as a member.
    my $fa = $f->make('FieldAccess', field_index => 0, field_stash => 'Counter', inputs => []);
    my $v  = $f->make('Constant', value => '7', const_type => 'integer');
    my $s1 = $f->make('Assign', inputs => [$fa, $v]);
    my $s2 = $f->make('Assign', inputs => [$fa, $v]);

    $g->merge($s1);

    my %member = map { $_->id => 1 } $g->nodes()->@*;
    ok($member{$s1->id}, 'merged per-call node is a member');
    ok(!$member{$s2->id}, 'content-identical orphan per-call node is NOT a member');
};

subtest 'Graph::unmerge of a per-call node does not evict a content-identical sibling' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $g = Chalk::IR::Graph->new;

    my $fa = $f->make('FieldAccess', field_index => 0, field_stash => 'Counter', inputs => []);
    my $v  = $f->make('Constant', value => '7', const_type => 'integer');
    my $s1 = $f->make('Assign', inputs => [$fa, $v]);
    my $s2 = $f->make('Assign', inputs => [$fa, $v]);

    $g->merge($s1);
    $g->merge($s2);
    $g->unmerge($s2);

    my %member = map { $_->id => 1 } $g->nodes()->@*;
    ok($member{$s1->id}, 'sibling per-call node survives unmerge of the other');
    ok(!$member{$s2->id}, 'unmerged per-call node is gone');
};

done_testing;
