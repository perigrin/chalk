# ABOUTME: The backend chain/branch collectors must pick up EVERY statement-effect op,
# ABOUTME: not a hard-coded subset — a method Call in an if-branch was silently dropped.
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

# process_control_node, _collect_body_recursive, and Elaborate's
# _collect_chain_recursive each hard-coded VarDecl/Assign/CompoundAssign/
# If/Loop — missing Call (and RegexSubst/TryCatch). A statement-position
# method call inside an if-branch was never collected, so its field
# mutation was dropped (019eb6ff item 5). The collectors must read the
# shared %STATEMENT_EFFECT_OPS table.

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

# class C { field $n :param; method bump { $n = $n + 100 } method val { $n } }
# my $c = C->new(n => 5); if (1) { $c->bump } return $c->val;
# perl: 105 — the method call in the then-branch mutates the field.
subtest 'a method Call in an if-branch is collected and lowered' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_field('n', sigil => '$', type => 'Int', attributes => [':param']);

    # method bump { $n = $n + 100 }
    my $fa_rd = $f->make('FieldAccess', field_index => 0, field_stash => 'C', inputs => []);
    $fa_rd->set_representation('Int');
    my $sum = $f->make('Add', inputs => [$fa_rd, int_const($f, 100)]);
    $sum->set_representation('Int');
    my $fa_lv = $f->make('FieldAccess', field_index => 0, field_stash => 'C', inputs => []);
    $fa_lv->set_representation('Int');
    my $store = $f->make('Assign', inputs => [$fa_lv, $sum]);
    $store->set_representation('Int');
    my $bump = $cls->declare_method('bump', return_type => 'Int');
    $bump->graph->merge($f->make_cfg('Return', inputs => [$store]));

    # method val { $n }
    my $fa_val = $f->make('FieldAccess', field_index => 0, field_stash => 'C', inputs => []);
    $fa_val->set_representation('Int');
    my $val = $cls->declare_method('val', return_type => 'Int');
    $val->graph->merge($f->make_cfg('Return', inputs => [$fa_val]));

    $mop->seal;

    # my $c = C->new(n => 5);
    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'C', param_names => ['n'], inputs => [int_const($f, 5)]);
    $new->set_representation('Object');
    my $nc = $f->make('Constant', value => '$c', const_type => 'string');
    my $vc = $f->make('VarDecl', inputs => [$nc, $new]);
    $vc->set_representation('Object');

    # if (1) { $c->bump }
    my $cond = int_const($f, 1);
    my $cond_b = $f->make('NumGt', inputs => [$cond, int_const($f, 0)]);
    $cond_b->set_representation('Bool');
    my $if_node = $f->make('If', inputs => [$vc, $cond_b]);
    my $proj0 = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1 = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    my $rc1 = $f->make('PadAccess', targ => 0, varname => '$c', inputs => [$vc]);
    $rc1->set_representation('Object');
    my $bump_call = $f->make('Call', dispatch_kind => 'method', name => 'bump',
        class_name => 'C', inputs => [$rc1]);
    $bump_call->set_representation('Int');
    $bump_call->set_control_in($proj0);   # the then-branch body

    # return $c->val
    my $rc2 = $f->make('PadAccess', targ => 0, varname => '$c', inputs => [$vc]);
    $rc2->set_representation('Object');
    my $val_call = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'C', inputs => [$rc2]);
    $val_call->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$val_call]);
    $if_node->set_control_in($vc);
    $vc->set_control_in($new);
    $ret->set_control_in($if_node);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret, mop => $mop));
    is($exit, 0, 'lli exits 0') or diag $out;
    is($out, 'Int:105', 'the branch method call mutated the field (perl: 105)');
};

done_testing;
