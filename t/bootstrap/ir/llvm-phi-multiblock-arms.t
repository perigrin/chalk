# ABOUTME: Phi-arm and loop-init values that expand to multiple blocks (bounds-checked
# ABOUTME: Subscript etc.) must lower while their host block is open, with labels re-captured.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Lowering a value can open new basic blocks (bounds-checked Subscript,
# And/Or short-circuits, ternaries). The phi/loop wiring sites historically
# lowered such values AFTER the host block's terminator was already set:
# the value's own control flow clobbers that terminator, the continuation
# tail is left unterminated, and the phi's incoming label still names the
# original block (whole-branch review I5). The fix is the _lower_and/_lower_or
# pattern: lower while the host block is open, re-capture the current label
# afterwards, and only then set the branch terminator.

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

# my $n = 1; my $x = $n > 0 ? [42]->[0] : 7; return $x;
# The then-arm is a bounds-checked Subscript — a multi-block value wired by
# the explicit-Region-phi path. perl: 42.
subtest 'if-merge explicit Phi with a multi-block then-arm (I5)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $nn = $f->make('Constant', value => '$n', const_type => 'string');
    my $vn = $f->make('VarDecl', inputs => [$nn, int_const($f, 1)]);
    $vn->set_representation('Int');

    my $rn = $f->make('PadAccess', targ => 0, varname => '$n', inputs => [$vn]);
    $rn->set_representation('Int');
    my $cmp = $f->make('NumGt', inputs => [$rn, int_const($f, 0)]);
    $cmp->set_representation('Bool');

    my $aref = $f->make('ArrayRef', inputs => [int_const($f, 42)]);
    $aref->set_representation('ArrayRef');
    my $sub = $f->make('Subscript', inputs => [$aref, int_const($f, 0)]);
    $sub->set_representation('Int');

    my $c7 = int_const($f, 7);

    my $if_node = $f->make('If', inputs => [$vn, $cmp]);
    my $proj0 = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1 = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    my $phi = $f->make('Phi', region => $region, values => [$sub, $c7]);
    $phi->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$phi]);
    $if_node->set_control_in($vn);
    $ret->set_control_in($if_node);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0 (valid IR)') or diag($out);
    is($out, 'Int:42', 'multi-block then-arm value flows through the merge phi (perl: 42)');
};

# my $s = 0; my $n = [3]->[0]; while ($n > 0) { $s += $n; $n-- } return $s;
# The loop phi INIT value is a multi-block Subscript lowered in the
# preheader. perl: 3+2+1 = 6.
subtest 'loop phi with a multi-block init value (I5)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $aref = $f->make('ArrayRef', inputs => [int_const($f, 3)]);
    $aref->set_representation('ArrayRef');
    my $n_init = $f->make('Subscript', inputs => [$aref, int_const($f, 0)]);
    $n_init->set_representation('Int');

    my $one = int_const($f, 1);

    my $sn = $f->make('Constant', value => '$s', const_type => 'string');
    my $vs = $f->make('VarDecl', inputs => [$sn, int_const($f, 0)]);
    $vs->set_representation('Int');
    my $rs0 = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs0->set_representation('Int');

    my $loop = $f->make('Loop', inputs => [$vs, undef]);

    my $n_phi = $f->make('Phi', region => $loop, values => [$n_init]);
    $n_phi->set_representation('Int');
    my $s_phi = $f->make('Phi', region => $loop, values => [$rs0]);
    $s_phi->set_representation('Int');

    my $cmp = $f->make('NumGt', inputs => [$n_phi, int_const($f, 0)]);
    $cmp->set_representation('Bool');

    my $s_new = $f->make('Add', inputs => [$s_phi, $n_phi]);
    $s_new->set_representation('Int');
    my $n_new = $f->make('Subtract', inputs => [$n_phi, $one]);
    $n_new->set_representation('Int');

    $n_phi->set_backedge($n_new);
    $s_phi->set_backedge($s_new);

    my $body_proj = $f->make('Proj', inputs => [$loop], index => 0);
    my $exit_proj = $f->make('Proj', inputs => [$loop], index => 1);
    my $exit_region = $f->make('Region', inputs => [$exit_proj]);
    $loop->set_region($exit_region);

    $n_new->set_control_in($body_proj);
    $s_new->set_control_in($body_proj);

    my $ret = $f->make_cfg('Return', inputs => [$s_phi]);
    $loop->set_control_in($vs);
    $ret->set_control_in($loop);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0 (valid IR)') or diag($out);
    is($out, 'Int:6', 'multi-block init value reaches the loop phi (perl: 6)');
};

# my @a = (0,5); my $s = 0; my $n = 1; while ($n > 0) { $s = $a[$n]; $n-- }
# return $s;  The s-phi BACKEDGE value is a multi-block Subscript lowered at
# the body tail. perl: $a[1] = 5.
subtest 'loop phi with a multi-block backedge value (I5)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $aref = $f->make('ArrayRef', inputs => [int_const($f, 0), int_const($f, 5)]);
    $aref->set_representation('ArrayRef');

    my $one = int_const($f, 1);

    my $sn = $f->make('Constant', value => '$s', const_type => 'string');
    my $vs = $f->make('VarDecl', inputs => [$sn, int_const($f, 0)]);
    $vs->set_representation('Int');
    my $rs0 = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs0->set_representation('Int');

    my $loop = $f->make('Loop', inputs => [$vs, undef]);

    my $n_phi = $f->make('Phi', region => $loop, values => [$one]);
    $n_phi->set_representation('Int');
    my $s_phi = $f->make('Phi', region => $loop, values => [$rs0]);
    $s_phi->set_representation('Int');

    my $cmp = $f->make('NumGt', inputs => [$n_phi, int_const($f, 0)]);
    $cmp->set_representation('Bool');

    my $s_new = $f->make('Subscript', inputs => [$aref, $n_phi]);
    $s_new->set_representation('Int');
    my $n_new = $f->make('Subtract', inputs => [$n_phi, $one]);
    $n_new->set_representation('Int');

    $n_phi->set_backedge($n_new);
    $s_phi->set_backedge($s_new);

    my $body_proj = $f->make('Proj', inputs => [$loop], index => 0);
    my $exit_proj = $f->make('Proj', inputs => [$loop], index => 1);
    my $exit_region = $f->make('Region', inputs => [$exit_proj]);
    $loop->set_region($exit_region);

    $n_new->set_control_in($body_proj);
    $s_new->set_control_in($body_proj);

    my $ret = $f->make_cfg('Return', inputs => [$s_phi]);
    $loop->set_control_in($vs);
    $ret->set_control_in($loop);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0 (valid IR)') or diag($out);
    is($out, 'Int:5', 'multi-block backedge value reaches the loop phi (perl: 5)');
};

done_testing;
