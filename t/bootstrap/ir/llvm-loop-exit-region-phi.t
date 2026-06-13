# ABOUTME: A loop-exit Region's only predecessor is the loop header, so a 2-arm exit phi
# ABOUTME: (body-end + preheader) would name non-predecessor blocks — must die loudly.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

# _wire_region_phis (the loop-exit variant) emitted a Region phi with
# incoming arms [body_end_label, preheader_label]. But the loop EXIT block's
# sole predecessor is the loop HEADER (the false-condition branch) — neither
# body-end nor preheader branches to it — so any phi it emitted named
# non-predecessor blocks (invalid IR). Real loops never attach a phi to the
# exit Region (loop-carried values flow through the HEADER phis, which the
# loop body and post-loop reads consume directly), so this was latent. If a
# producer ever attaches one, it must fail with a diagnostic, not emit
# structurally-broken IR (019eb6ff item 2).

sub int_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

subtest 'an exit-Region phi consumer dies with a diagnostic' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # my $i = 0; while ($i < 3) { $i = $i + 1 } return $i;
    my $ni = $f->make('Constant', value => '$i', const_type => 'string');
    my $vi = $f->make('VarDecl', inputs => [$ni, int_const($f, 0)]);
    $vi->set_representation('Int');
    my $ri0 = $f->make('PadAccess', targ => 0, varname => '$i', inputs => [$vi]);
    $ri0->set_representation('Int');

    my $loop = $f->make('Loop', inputs => [$vi, undef]);
    my $i_phi = $f->make('Phi', region => $loop, values => [$ri0]);
    $i_phi->set_representation('Int');
    my $cmp = $f->make('NumLt', inputs => [$i_phi, int_const($f, 3)]);
    $cmp->set_representation('Bool');
    my $i_new = $f->make('Add', inputs => [$i_phi, int_const($f, 1)]);
    $i_new->set_representation('Int');
    $i_phi->set_backedge($i_new);

    my $body_proj = $f->make('Proj', inputs => [$loop], index => 0);
    my $exit_proj = $f->make('Proj', inputs => [$loop], index => 1);
    my $exit_region = $f->make('Region', inputs => [$exit_proj]);
    $loop->set_region($exit_region);
    $i_new->set_control_in($body_proj);

    # Adversarially attach a Phi to the EXIT region (the shape no real
    # producer makes — the thing the guard must reject).
    my $exit_phi = $f->make('Phi', region => $exit_region, values => [$i_phi, $ri0]);
    $exit_phi->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$exit_phi]);
    $loop->set_control_in($vi);
    $ret->set_control_in($loop);

    my $err;
    eval { Chalk::Target::LLVM->lower($ret); 1 } or $err = $@;
    like($err, qr/exit.*Region|loop.exit.*phi|single predecessor|header/i,
        'attaching a phi to a loop-exit Region dies with a structural diagnostic');
};

done_testing;
