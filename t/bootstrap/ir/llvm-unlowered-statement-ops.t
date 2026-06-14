# ABOUTME: Statement-effect ops with no runtime-free lowering (NotMatch/BacktickExpr/
# ABOUTME: TryCatch) must die with a GAP: message so the corpus harness records a GAP.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

# %STATEMENT_EFFECT_OPS gives these ops per-call identity AND makes the
# control collectors route them to lower_value (019eb6ff). But the backend
# has no runtime-free lowering for NotMatch (!~), BacktickExpr (qx), or
# TryCatch (try/catch). A statement-position occurrence must therefore die
# with an honest GAP: message — the corpus L-corner classifies a GAP die as
# a gap-map entry, whereas the old generic "cannot lower" die misdirects
# debugging (whole-branch review I1; matters for the Phase-4 try/catch tier).

sub str_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => $val, const_type => 'string');
    $c->set_representation('Str');
    return $c;
}

subtest 'NotMatch dies with a GAP message, naming the op' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $s = str_const($f, 'abc');
    my $qr = $f->make('Constant', value => 'b', const_type => 'regex');
    $qr->set_representation('Regex');
    my $nm = $f->make('NotMatch', inputs => [$s, $qr]);
    $nm->set_representation('Bool');
    my $ret = $f->make_cfg('Return', inputs => [$nm]);
    $ret->set_control_in($nm);

    my $err;
    eval { Chalk::Target::LLVM->lower($ret); 1 } or $err = $@;
    like($err, qr/^GAP:/m, 'die is a GAP, not a generic backend error');
    like($err, qr/NotMatch/, 'the GAP names the unlowered op');
};

subtest 'BacktickExpr dies with a GAP message, naming the op' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $cmd = str_const($f, 'echo hi');
    my $bt = $f->make('BacktickExpr', inputs => [$cmd]);
    $bt->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$bt]);
    $ret->set_control_in($bt);

    my $err;
    eval { Chalk::Target::LLVM->lower($ret); 1 } or $err = $@;
    like($err, qr/^GAP:/m, 'die is a GAP, not a generic backend error');
    like($err, qr/BacktickExpr/, 'the GAP names the unlowered op');
};

subtest 'TryCatch dies with a GAP message, naming the op' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $body = str_const($f, 'x');
    my $tc = $f->make('TryCatch', inputs => [$body]);
    $tc->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$tc]);
    $ret->set_control_in($tc);

    my $err;
    eval { Chalk::Target::LLVM->lower($ret); 1 } or $err = $@;
    like($err, qr/^GAP:/m, 'die is a GAP, not a generic backend error');
    like($err, qr/TryCatch/, 'the GAP names the unlowered op');
};

done_testing;
