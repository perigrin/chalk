# ABOUTME: The LLVM backend builds its class registry from a sealed Chalk::MOP directly
# ABOUTME: (lower(mop => $mop) + Call.class_name) — no ClassInfo metadata rides the graph.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::MOP;
use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# docs/plans/2026-06-11-llvm-reads-mop-directly.md: class structure is
# compile-time context. The backend receives the sealed MOP alongside the
# graph and resolves Call.class_name against a registry built from
# MOP::Class/Method/Field/Phaser::Adjust — the ClassInfo bridge retires.

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

sub int_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

# class Pt { field $x :param :reader; field $y;
#            ADJUST { $y = $x + 1 }
#            method val { $y } }
# my $p = Pt->new(x => 5); return $p->val + $p->x;  => perl: 6 + 5 = 11
subtest 'field + reader + ADJUST + method via the sealed MOP' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pt');

    $cls->declare_field('x', sigil => '$', type => 'Int',
        attributes => [':param', ':reader']);
    $cls->declare_field('y', sigil => '$', type => 'Int', attributes => []);

    # method val { $y }
    my $fa_y = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_y->set_representation('Int');
    my $m = $cls->declare_method('val', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$fa_y]));

    # ADJUST { $y = $x + 1 }
    my $fa_x = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []);
    $fa_x->set_representation('Int');
    my $add = $f->make('Add', inputs => [$fa_x, int_const($f, 1)]);
    $add->set_representation('Int');
    my $fa_y_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_y_lv->set_representation('Int');
    my $st = $f->make('Assign', inputs => [$fa_y_lv, $add]);
    $st->set_representation('Int');
    my $adj = $cls->declare_adjust();
    $adj->graph->merge($st);

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Pt', param_names => ['x'], inputs => [int_const($f, 5)]);
    $new->set_representation('Object');
    my $val = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Pt', inputs => [$new]);
    $val->set_representation('Int');
    my $x = $f->make('Call', dispatch_kind => 'method', name => 'x',
        class_name => 'Pt', inputs => [$new]);
    $x->set_representation('Int');
    my $sum = $f->make('Add', inputs => [$val, $x]);
    $sum->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$sum]);

    my $ll = Chalk::Target::LLVM->lower($ret, mop => $mop);
    unlike($ll, qr/\bSV\b|Perl_|libperl/, '.ll is libperl-free');
    my ($out, $exit) = run_lli($ll);
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:11', 'ADJUST + method + :reader all dispatch (perl: 6+5=11)');
};

# class Base { method seven { 7 } }  class Kid :isa(Base) {}
# return Kid->new->seven;  => perl: 7
subtest ':isa inheritance through the MOP registry' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;

    my $base = $mop->declare_class('Base');
    my $bm = $base->declare_method('seven', return_type => 'Int');
    $bm->graph->merge($f->make_cfg('Return', inputs => [int_const($f, 7)]));

    $mop->declare_class('Kid', parent_name => 'Base');

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Kid', inputs => []);
    $new->set_representation('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'seven',
        class_name => 'Kid', inputs => [$new]);
    $call->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:7', 'inherited method dispatches through the child vtable (perl: 7)');
};

# Multi-statement ADJUST bodies are ordered by their control chain.
# ADJUST { $p = $x; $x = 9; $q = $x }  =>  p=5, q=9, val: p+q = 14
subtest 'multi-statement ADJUST body in control-chain order' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pt');

    $cls->declare_field('x', sigil => '$', type => 'Int', attributes => [':param']);
    $cls->declare_field('p', sigil => '$', type => 'Int', attributes => []);
    $cls->declare_field('q', sigil => '$', type => 'Int', attributes => []);

    my $fa_x = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []);
    $fa_x->set_representation('Int');
    my $fa_p_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_p_lv->set_representation('Int');
    my $fa_q_lv = $f->make('FieldAccess', field_index => 2, field_stash => 'Pt', inputs => []);
    $fa_q_lv->set_representation('Int');

    my $st_p = $f->make('Assign', inputs => [$fa_p_lv, $fa_x]);
    $st_p->set_representation('Int');
    my $st_x = $f->make('Assign',
        inputs => [$f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []), int_const($f, 9)]);
    $st_x->set_representation('Int');
    my $st_q = $f->make('Assign', inputs => [$fa_q_lv, $fa_x]);
    $st_q->set_representation('Int');

    # Thread the body order: st_p -> st_x -> st_q.
    $st_x->set_control_in($st_p);
    $st_q->set_control_in($st_x);

    my $adj = $cls->declare_adjust();
    $adj->graph->merge($_) for ($st_p, $st_x, $st_q);

    my $fa_p = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_p->set_representation('Int');
    my $fa_q = $f->make('FieldAccess', field_index => 2, field_stash => 'Pt', inputs => []);
    $fa_q->set_representation('Int');
    my $body = $f->make('Add', inputs => [$fa_p, $fa_q]);
    $body->set_representation('Int');
    my $m = $cls->declare_method('val', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body]));

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Pt', param_names => ['x'], inputs => [int_const($f, 5)]);
    $new->set_representation('Object');
    my $val = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Pt', inputs => [$new]);
    $val->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:14', 'statements ran in chain order (perl: 5 + 9 = 14)');
};

# class Top { method seven { 7 } } class Mid :isa(Top) {} class Kid :isa(Mid) {}
# return Kid->new->seven;  => perl: 7.  Class names chosen so the GRANDCHILD
# sorts before its parent ("Kid" lt "Mid") — a single-pass flatten over
# sorted names copies Mid's methods into Kid before Mid has inherited Top's.
subtest 'grandparent inheritance, child sorts before parent (review)' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;

    my $top = $mop->declare_class('Top');
    my $tm = $top->declare_method('seven', return_type => 'Int');
    $tm->graph->merge($f->make_cfg('Return', inputs => [int_const($f, 7)]));

    $mop->declare_class('Mid', parent_name => 'Top');
    $mop->declare_class('Kid', parent_name => 'Mid');

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Kid', inputs => []);
    $new->set_representation('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'seven',
        class_name => 'Kid', inputs => [$new]);
    $call->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:7', 'the grandparent method reaches the grandchild vtable (perl: 7)');
};

# field $y = 41 (default, no :param): the default-value lowering path
# through MOP::Field->default_value. perl: 41.
subtest 'field default value lowers through the MOP registry (review)' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Dft');

    my $c41 = int_const($f, 41);
    $cls->declare_field('y', sigil => '$', type => 'Int', attributes => [],
        has_default => true, default_value => $c41);

    my $fa_y = $f->make('FieldAccess', field_index => 0, field_stash => 'Dft', inputs => []);
    $fa_y->set_representation('Int');
    my $m = $cls->declare_method('val', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$fa_y]));

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Dft', inputs => []);
    $new->set_representation('Object');
    my $val = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Dft', inputs => [$new]);
    $val->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$val]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:41', 'the default expression initializes the field (perl: 41)');
};

# A statement-effect node appearing as an INPUT of an ADJUST statement
# (e.g. the rhs of a store) is a sub-expression, not a body statement —
# collecting from the input closure would see a spurious second chain head
# and die GAP on a legitimate single-statement body (review).
subtest 'phaser body collection ignores statement-effect sub-expressions' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pt');

    my $rhs_call = $f->make('Call', dispatch_kind => 'builtin', name => 'length',
        inputs => [$f->make('Constant', value => 'abc', const_type => 'string')]);
    my $fa_lv = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []);
    $fa_lv->set_representation('Int');
    my $st = $f->make('Assign', inputs => [$fa_lv, $rhs_call]);
    $st->set_representation('Int');

    my $adj = $cls->declare_adjust();
    $adj->graph->merge($st);   # ONE statement; the Call rides as its input
    $mop->seal;

    my $stmts = Chalk::Target::LLVM::_phaser_body_in_control_order($adj);
    is(scalar @$stmts, 1, 'exactly one body statement collected');
    is($stmts->[0]->id, $st->id, 'and it is the merged store, not its rhs Call');
};

subtest 'guards: unsealed MOP and Return-less method die loudly' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    $mop->declare_class('Pt');
    my $ret = $f->make_cfg('Return', inputs => [int_const($f, 1)]);

    my $err;
    eval { Chalk::Target::LLVM->lower($ret, mop => $mop); 1 } or $err = $@;
    like($err, qr/seal/i, 'an unsealed MOP is rejected');

    my $mop2 = Chalk::MOP->new;
    my $cls2 = $mop2->declare_class('Pt');
    $cls2->declare_method('val', return_type => 'Int');   # graph has no Return
    $mop2->seal;
    my $err2;
    eval { Chalk::Target::LLVM->lower($ret, mop => $mop2); 1 } or $err2 = $@;
    like($err2, qr/GAP|Return/, 'a method graph without a Return dies with a diagnostic');

    # MULTIPLE Returns: Graph::returns() iterates a hash, so picking "the
    # first" is nondeterministic — the contract is exactly one (review).
    my $f3   = Chalk::IR::NodeFactory->new;
    my $mop3 = Chalk::MOP->new;
    my $cls3 = $mop3->declare_class('Pt');
    my $m3 = $cls3->declare_method('val', return_type => 'Int');
    $m3->graph->merge($f3->make_cfg('Return', inputs => [int_const($f3, 1)]));
    $m3->graph->merge($f3->make_cfg('Return', inputs => [int_const($f3, 2)]));
    $mop3->seal;
    my $err3;
    eval { Chalk::Target::LLVM->lower($ret, mop => $mop3); 1 } or $err3 = $@;
    like($err3, qr/GAP.*Return|Return.*GAP|exactly one/i,
        'a method graph with two Returns dies instead of picking one nondeterministically');

    # A class_name Call lowered WITHOUT a mop fails the (empty) registry
    # lookup loudly — the deleted ClassInfo bridge does not silently revive.
    my $f4 = Chalk::IR::NodeFactory->new;
    my $ghost = $f4->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Ghost', inputs => []);
    $ghost->set_representation('Object');
    my $ret4 = $f4->make_cfg('Return', inputs => [$ghost]);
    my $err4;
    eval { Chalk::Target::LLVM->lower($ret4); 1 } or $err4 = $@;
    like($err4, qr/undeclared class 'Ghost'/,
        'a class_name Call without a mop dies at the registry lookup');
};

done_testing;
