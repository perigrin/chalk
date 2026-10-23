# ABOUTME: An inlined callee reads its own lexicals, never a caller's that shares an id:
# ABOUTME: a callee VarDecl#1 next to a caller VarDecl#1 still yields the callee's value.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Target::LLVM;
use Chalk::MOP;

my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "lli not found at $LLI (set LLI)" unless -x $LLI;

sub ic ($f, $v) { my $c = $f->make('Constant', value => "$v", const_type => 'integer'); $c->set_stamp('Int'); $c }
sub sc ($f, $v) { my $c = $f->make('Constant', value => $v, const_type => 'string'); $c->set_stamp('Str'); $c }
sub pa ($f, $vd, $n) {
    my $p = $f->make('PadAccess', targ => 0, sigil => '$', symbol => $n, inputs => [$vd]);
    $p->set_stamp('Int');
    $p;
}

# THE CALLER'S var_table WAS COPIED INTO THE CALLEE (review of 4e1e9969).
# Each graph numbers its VarDecls from its own factory, so the callee's
# `my $y = 7` and the caller's `my $x = 5` are both VarDecl#1; with the
# caller's entry already there, the callee's $y read the caller's 5, and
# `$y + $z` gave 8 for 10.
my $g  = Chalk::IR::NodeFactory->new;
my $gs = $g->make('Start');
my $vy = $g->make('VarDecl', inputs => [sc($g, '$y'), ic($g, 7)]); $vy->set_stamp('Int');
my $vz = $g->make('VarDecl', inputs => [sc($g, '$z'), ic($g, 0)]); $vz->set_stamp('Int');
my $az = $g->make('Assign', inputs => [pa($g, $vz, 'z'), ic($g, 3)]);
$az->set_stamp('Int');
$az->set_control_in($gs);
my $sum = $g->make('Add', inputs => [pa($g, $vy, 'y'), pa($g, $vz, 'z')]); $sum->set_stamp('Int');
my $gr  = $g->make_cfg('Return', inputs => [$sum]);
$gr->set_control_in($az);
my $target = Chalk::MOP->new->for_class('main')->declare_sub('f',
    graph => Chalk::IR::Graph->new(start => $gs, returns => [$gr]));

my $f  = Chalk::IR::NodeFactory->new;
my $s  = $f->make('Start');
my $vx = $f->make('VarDecl', inputs => [sc($f, '$x'), ic($f, 5)]); $vx->set_stamp('Int');
$vx->set_control_in($s);
is($vx->id, $vy->id, 'the caller and callee VarDecls share an id (the collision this pins)');
my $call = $f->make('Call', dispatch_kind => 'direct', name => 'main::f', target => $target);
$call->set_stamp('Int');
$call->set_control_in($vx);
my $str = $f->make('Coerce', inputs => [$call], from_repr => 'Int', to_repr => 'Str'); $str->set_stamp('Str');
my $p   = $f->make('Print', inputs => [$str]);
$p->set_control_in($call);
my $nl  = $f->make('Print', inputs => [sc($f, "\n")]);
$nl->set_control_in($p);
my $u = $f->make('Constant', value => undef, const_type => 'undef'); $u->set_stamp('Undef');
my $r = $f->make_cfg('Return', inputs => [$u]);
$r->set_control_in($nl);

my $ll = Chalk::Target::LLVM->lower($r, program_mode => 1);
my ($fh, $path) = tempfile(SUFFIX => '.ll', UNLINK => 1);
print $fh $ll;
close $fh;
is(scalar qx($LLI $path 2>&1), "10\n", "the callee's \$y is its own 7: 7 + 3");

done_testing;
