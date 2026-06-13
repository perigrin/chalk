# ABOUTME: A subclass constructor runs the parent's ADJUST blocks too (base-first MRO);
# ABOUTME: the registry consulted only the leaf class's adjusts, skipping inherited ones.
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

# Perl runs ADJUST blocks base-class-first during construction. The
# MOP-direct registry built each class's adjusts from $cls->adjust_blocks
# (own blocks only), so `Child->new` never ran Base's ADJUST (019eb6ff
# item 6). resolve_adjust_blocks() walks the superclass chain base-first.

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

# class Base { field $b :param; field $d; ADJUST { $d = $b + 1 } }
# class Kid :isa(Base) { field $k; ADJUST { $k = $b + 10 } method sum { $d + $k } }
# my $o = Kid->new(b => 5); return $o->sum;   perl: d=6, k=15 -> 21
subtest "parent ADJUST runs on a child constructor" => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;

    my $base = $mop->declare_class('Base');
    $base->declare_field('b', sigil => '$', type => 'Int', attributes => [':param']);
    $base->declare_field('d', sigil => '$', type => 'Int', attributes => []);
    # ADJUST { $d = $b + 1 }
    my $b_rd = $f->make('FieldAccess', field_index => 0, field_stash => 'Base', inputs => []);
    $b_rd->set_representation('Int');
    my $d_val = $f->make('Add', inputs => [$b_rd, int_const($f, 1)]);
    $d_val->set_representation('Int');
    my $d_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Base', inputs => []);
    $d_lv->set_representation('Int');
    my $d_st = $f->make('Assign', inputs => [$d_lv, $d_val]);
    $d_st->set_representation('Int');
    $base->declare_adjust()->graph->merge($d_st);

    my $kid = $mop->declare_class('Kid', parent_name => 'Base');
    $kid->declare_field('k', sigil => '$', type => 'Int', attributes => []);
    # ADJUST { $k = $b + 10 } — reads the inherited :param field b (index 0)
    my $b_rd2 = $f->make('FieldAccess', field_index => 0, field_stash => 'Kid', inputs => []);
    $b_rd2->set_representation('Int');
    my $k_val = $f->make('Add', inputs => [$b_rd2, int_const($f, 10)]);
    $k_val->set_representation('Int');
    my $k_lv = $f->make('FieldAccess', field_index => 2, field_stash => 'Kid', inputs => []);
    $k_lv->set_representation('Int');
    my $k_st = $f->make('Assign', inputs => [$k_lv, $k_val]);
    $k_st->set_representation('Int');
    $kid->declare_adjust()->graph->merge($k_st);

    # method sum { $d + $k }  (Kid struct: b=0, d=1, k=2)
    my $d_rd = $f->make('FieldAccess', field_index => 1, field_stash => 'Kid', inputs => []);
    $d_rd->set_representation('Int');
    my $k_rd = $f->make('FieldAccess', field_index => 2, field_stash => 'Kid', inputs => []);
    $k_rd->set_representation('Int');
    my $sum = $f->make('Add', inputs => [$d_rd, $k_rd]);
    $sum->set_representation('Int');
    my $sum_m = $kid->declare_method('sum', return_type => 'Int');
    $sum_m->graph->merge($f->make_cfg('Return', inputs => [$sum]));

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Kid', param_names => ['b'], inputs => [int_const($f, 5)]);
    $new->set_representation('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'sum',
        class_name => 'Kid', inputs => [$new]);
    $call->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0') or diag $out;
    is($out, 'Int:21', 'both ADJUSTs ran (base d=6 + child k=15 = 21)');
};

# Child sorts ALPHABETICALLY before its parent: "Apple" lt "Zoo". The
# inherited ADJUST's FieldAccess(field_stash='Zoo') GEPs into %Zoo.obj from
# within @Apple__ADJUST — if struct types are emitted inline per class block
# in sort order, %Zoo.obj is referenced before it is defined (lli: "base
# element of getelementptr must be sized"). Struct type definitions must be
# hoisted ahead of all class bodies (review).
subtest "inherited ADJUST when child sorts before parent" => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;

    my $zoo = $mop->declare_class('Zoo');
    $zoo->declare_field('z', sigil => '$', type => 'Int', attributes => [':param']);
    $zoo->declare_field('d', sigil => '$', type => 'Int', attributes => []);
    my $z_rd = $f->make('FieldAccess', field_index => 0, field_stash => 'Zoo', inputs => []);
    $z_rd->set_representation('Int');
    my $d_val = $f->make('Add', inputs => [$z_rd, int_const($f, 1)]);
    $d_val->set_representation('Int');
    my $d_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Zoo', inputs => []);
    $d_lv->set_representation('Int');
    my $d_st = $f->make('Assign', inputs => [$d_lv, $d_val]);
    $d_st->set_representation('Int');
    $zoo->declare_adjust()->graph->merge($d_st);

    my $apple = $mop->declare_class('Apple', parent_name => 'Zoo');
    # method val { $d }  (Apple struct: z=0, d=1)
    my $d_rd = $f->make('FieldAccess', field_index => 1, field_stash => 'Apple', inputs => []);
    $d_rd->set_representation('Int');
    my $val_m = $apple->declare_method('val', return_type => 'Int');
    $val_m->graph->merge($f->make_cfg('Return', inputs => [$d_rd]));

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Apple', param_names => ['z'], inputs => [int_const($f, 20)]);
    $new->set_representation('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Apple', inputs => [$new]);
    $call->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0') or diag $out;
    is($out, 'Int:21', 'parent ADJUST ran across the sort-order boundary (z=20 -> d=21)');
};

# Three levels: G { field $g :param } -> Mid :isa(G) { field $m; ADJUST { $m = $g + 1 } }
# -> Kid :isa(Mid) { field $k; ADJUST { $k = $m + 1 } method val { $k } }
# Kid->new(g => 40): m = 41, k = 42. The Mid ADJUST (flattened into Kid)
# GEPs %Mid.obj; the grandparent field must be at the right flattened slot.
subtest "three-level field + ADJUST inheritance" => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;

    my $g = $mop->declare_class('G');
    $g->declare_field('g', sigil => '$', type => 'Int', attributes => [':param']);

    my $mid = $mop->declare_class('Mid', parent_name => 'G');
    $mid->declare_field('m', sigil => '$', type => 'Int', attributes => []);
    # ADJUST { $m = $g + 1 } — $g is the inherited field at flattened slot 0
    my $g_rd = $f->make('FieldAccess', field_index => 0, field_stash => 'Mid', inputs => []);
    $g_rd->set_representation('Int');
    my $m_val = $f->make('Add', inputs => [$g_rd, int_const($f, 1)]);
    $m_val->set_representation('Int');
    my $m_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Mid', inputs => []);
    $m_lv->set_representation('Int');
    my $m_st = $f->make('Assign', inputs => [$m_lv, $m_val]);
    $m_st->set_representation('Int');
    $mid->declare_adjust()->graph->merge($m_st);

    my $kid = $mop->declare_class('Kid', parent_name => 'Mid');
    $kid->declare_field('k', sigil => '$', type => 'Int', attributes => []);
    # ADJUST { $k = $m + 1 } — $m at flattened slot 1
    my $m_rd = $f->make('FieldAccess', field_index => 1, field_stash => 'Kid', inputs => []);
    $m_rd->set_representation('Int');
    my $k_val = $f->make('Add', inputs => [$m_rd, int_const($f, 1)]);
    $k_val->set_representation('Int');
    my $k_lv = $f->make('FieldAccess', field_index => 2, field_stash => 'Kid', inputs => []);
    $k_lv->set_representation('Int');
    my $k_st = $f->make('Assign', inputs => [$k_lv, $k_val]);
    $k_st->set_representation('Int');
    $kid->declare_adjust()->graph->merge($k_st);

    # method val { $k }  (Kid struct: g=0, m=1, k=2)
    my $k_rd = $f->make('FieldAccess', field_index => 2, field_stash => 'Kid', inputs => []);
    $k_rd->set_representation('Int');
    my $val_m = $kid->declare_method('val', return_type => 'Int');
    $val_m->graph->merge($f->make_cfg('Return', inputs => [$k_rd]));

    $mop->seal;

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Kid', param_names => ['g'], inputs => [int_const($f, 40)]);
    $new->set_representation('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Kid', inputs => [$new]);
    $call->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0') or diag $out;
    is($out, 'Int:42', 'grandparent + parent ADJUSTs chained (g=40 -> m=41 -> k=42)');
};

# An inherited :reader method called on a child; a child overriding a method
# while inheriting a field (review coverage gaps 4).
subtest "inherited :reader and field-inheriting override" => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;

    my $base = $mop->declare_class('B');
    $base->declare_field('v', sigil => '$', type => 'Int', attributes => [':param', ':reader']);
    # method tag { 1 }
    my $one_b = int_const($f, 1);
    my $tag_b = $base->declare_method('tag', return_type => 'Int');
    $tag_b->graph->merge($f->make_cfg('Return', inputs => [$one_b]));

    my $kid = $mop->declare_class('K', parent_name => 'B');
    # K overrides tag { $v + 100 } while inheriting field v (slot 0)
    my $v_rd = $f->make('FieldAccess', field_index => 0, field_stash => 'K', inputs => []);
    $v_rd->set_representation('Int');
    my $ov = $f->make('Add', inputs => [$v_rd, int_const($f, 100)]);
    $ov->set_representation('Int');
    my $tag_k = $kid->declare_method('tag', return_type => 'Int');
    $tag_k->graph->merge($f->make_cfg('Return', inputs => [$ov]));

    $mop->seal;

    # my $o = K->new(v => 5); return $o->v + $o->tag;  reader 5 + override 105 = 110
    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'K', param_names => ['v'], inputs => [int_const($f, 5)]);
    $new->set_representation('Object');
    my $rdr = $f->make('Call', dispatch_kind => 'method', name => 'v',
        class_name => 'K', inputs => [$new]);
    $rdr->set_representation('Int');
    my $tag = $f->make('Call', dispatch_kind => 'method', name => 'tag',
        class_name => 'K', inputs => [$new]);
    $tag->set_representation('Int');
    my $sum = $f->make('Add', inputs => [$rdr, $tag]);
    $sum->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$sum]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0') or diag $out;
    is($out, 'Int:110', 'inherited :reader (5) + field-inheriting override (105) = 110');
};

done_testing;
