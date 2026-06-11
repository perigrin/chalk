# ABOUTME: ADJUST blocks lower once as a per-class @Cls__ADJUST(i8*) function called per
# ABOUTME: new; inline main-ctx lowering cache-skipped the second object's ADJUST stores.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::MOP;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Lowering ADJUST bodies inline on the MAIN context (per Call(new)) shares
# the main value cache across constructions: the second new of the same
# class cache-hits the ADJUST body's statement nodes and silently skips the
# second object's stores (whole-branch review I6). The fix synthesizes ONE
# @Cls__ADJUST(i8* %self) function per class — lowered once in a fresh
# Context like a method body — and each Call(new) calls it after binding.

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

# class Pt { field $x :param; field $y; ADJUST { $y = $x + 1 }
#            method gety { $y } }
sub build_pt_mop {
    my ($f) = @_;

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pt');
    $cls->declare_field('x', sigil => '$', type => 'Int', attributes => [':param']);
    $cls->declare_field('y', sigil => '$', type => 'Int', attributes => []);

    my $fa_x = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []);
    $fa_x->set_representation('Int');
    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $add = $f->make('Add', inputs => [$fa_x, $c1]);
    $add->set_representation('Int');
    my $fa_y_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_y_lv->set_representation('Int');
    my $asg = $f->make('Assign', inputs => [$fa_y_lv, $add]);
    $asg->set_representation('Int');
    my $adj = $cls->declare_adjust();
    $adj->graph->merge($asg);

    my $fa_y_rd = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_y_rd->set_representation('Int');
    my $mi = $cls->declare_method('gety', return_type => 'Int');
    $mi->graph->merge($f->make_cfg('Return', inputs => [$fa_y_rd]));

    $mop->seal;
    return $mop;
}

# my $a = Pt->new(x => 5); return $a->gety;  => perl: 6
subtest 'single new runs ADJUST (sanity)' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = build_pt_mop($f);

    my $v5 = $f->make('Constant', value => '5', const_type => 'integer');
    $v5->set_representation('Int');
    my $new_a = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Pt', param_names => ['x'], inputs => [$v5]);
    $new_a->set_representation('Object');
    my $get_a = $f->make('Call', dispatch_kind => 'method', name => 'gety',
        class_name => 'Pt', inputs => [$new_a]);
    $get_a->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$get_a]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:6', 'ADJUST stores y = x + 1 (perl: 6)');
};

# my $a = Pt->new(x => 5); my $b = Pt->new(x => 100);
# return $a->gety + $b->gety;  => perl: 6 + 101 = 107
subtest 'second new of the same class runs ADJUST too (I6)' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = build_pt_mop($f);

    my $v5 = $f->make('Constant', value => '5', const_type => 'integer');
    $v5->set_representation('Int');
    my $v100 = $f->make('Constant', value => '100', const_type => 'integer');
    $v100->set_representation('Int');

    my $new_a = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Pt', param_names => ['x'], inputs => [$v5]);
    $new_a->set_representation('Object');
    my $new_b = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Pt', param_names => ['x'], inputs => [$v100]);
    $new_b->set_representation('Object');

    my $get_a = $f->make('Call', dispatch_kind => 'method', name => 'gety',
        class_name => 'Pt', inputs => [$new_a]);
    $get_a->set_representation('Int');
    my $get_b = $f->make('Call', dispatch_kind => 'method', name => 'gety',
        class_name => 'Pt', inputs => [$new_b]);
    $get_b->set_representation('Int');
    my $sum = $f->make('Add', inputs => [$get_a, $get_b]);
    $sum->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$sum]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:107', 'both objects get their own ADJUST stores (perl: 6+101=107)');
};

done_testing;
