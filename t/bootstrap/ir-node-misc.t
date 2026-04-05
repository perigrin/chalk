# ABOUTME: Tests for Call, Aggregate, Regex, and remaining computation nodes.
# ABOUTME: Verifies all non-BinOp/UnaryOp/Access computation node types.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Aggregate;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::AnonSub;
use Chalk::IR::Node::Regex;
use Chalk::IR::Node::RegexMatch;
use Chalk::IR::Node::RegexSubst;
use Chalk::IR::Node::TryCatch;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::BacktickExpr;
use Chalk::IR::Node::VarDecl;

my $arg = Chalk::IR::Node->new(id => 'arg_0');
my $call = Chalk::IR::Node::Call->new(id => 'call_0', dispatch_kind => 'method', name => 'foo', inputs => [$arg]);
is($call->operation(), 'Call', 'Call operation');
is($call->dispatch_kind(), 'method', 'Call dispatch_kind');
is($call->name(), 'foo', 'Call name');
like($call->content_hash(), qr/Call\|dispatch_kind=method\|name=foo/, 'Call content_hash');

my $hr = Chalk::IR::Node::HashRef->new(id => 'hr_0', inputs => []);
isa_ok($hr, 'Chalk::IR::Node::Aggregate', 'HashRef isa Aggregate');
is($hr->operation(), 'HashRef', 'HashRef operation');

my $ar = Chalk::IR::Node::ArrayRef->new(id => 'ar_0', inputs => []);
isa_ok($ar, 'Chalk::IR::Node::Aggregate', 'ArrayRef isa Aggregate');
is($ar->operation(), 'ArrayRef', 'ArrayRef operation');

my $interp = Chalk::IR::Node::Interpolate->new(id => 'int_0', inputs => []);
isa_ok($interp, 'Chalk::IR::Node::Aggregate', 'Interpolate isa Aggregate');
is($interp->operation(), 'Interpolate', 'Interpolate operation');

my $anon = Chalk::IR::Node::AnonSub->new(id => 'anon_0', graph => undef);
is($anon->operation(), 'AnonSub', 'AnonSub operation');
is($anon->graph(), undef, 'AnonSub graph initially undef');

my $rm = Chalk::IR::Node::RegexMatch->new(id => 'rm_0', inputs => [], flags => 'gi');
isa_ok($rm, 'Chalk::IR::Node::Regex', 'RegexMatch isa Regex');
is($rm->operation(), 'RegexMatch', 'RegexMatch operation');
is($rm->flags(), 'gi', 'RegexMatch flags');

my $rs = Chalk::IR::Node::RegexSubst->new(id => 'rs_0', inputs => [], flags => 's');
isa_ok($rs, 'Chalk::IR::Node::Regex', 'RegexSubst isa Regex');
is($rs->operation(), 'RegexSubst', 'RegexSubst operation');

my $tc = Chalk::IR::Node::TryCatch->new(id => 'tc_0', inputs => []);
is($tc->operation(), 'TryCatch', 'TryCatch operation');

my $pd = Chalk::IR::Node::PostfixDeref->new(id => 'pd_0', inputs => [], sigil => '@');
is($pd->operation(), 'PostfixDeref', 'PostfixDeref operation');
is($pd->sigil(), '@', 'PostfixDeref sigil');

my $ca = Chalk::IR::Node::CompoundAssign->new(id => 'ca_0', inputs => [], op => '+=');
is($ca->operation(), 'CompoundAssign', 'CompoundAssign operation');
is($ca->op(), '+=', 'CompoundAssign op');

my $bt = Chalk::IR::Node::BacktickExpr->new(id => 'bt_0', inputs => []);
is($bt->operation(), 'BacktickExpr', 'BacktickExpr operation');

my $vd = Chalk::IR::Node::VarDecl->new(id => 'vd_0', inputs => []);
is($vd->operation(), 'VarDecl', 'VarDecl operation');

done_testing();
