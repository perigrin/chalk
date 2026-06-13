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

done_testing;
