# ABOUTME: Tests for Chalk::IR data and access node classes.
# ABOUTME: Verifies Constant, Phi, PadAccess, FieldAccess, StashAccess, Subscript.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Access;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::FieldAccess;
use Chalk::IR::Node::StashAccess;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::Region;

my $c = Chalk::IR::Node::Constant->new(id => 'c_0', value => '42', stamp => 'Int', const_type => 'integer');
is($c->operation(), 'Constant', 'Constant operation');
is($c->value(), '42', 'Constant value');
is($c->const_type(), 'integer', 'Constant const_type');
is($c->stamp(), 'Int', 'Constant stamp');
like($c->content_hash(), qr/Constant\|const_type=integer\|value=42/, 'Constant content_hash includes const_type and value');

my $undef_c = Chalk::IR::Node::Constant->new(id => 'c_u', value => undef, stamp => 'Undef', const_type => 'string');
like($undef_c->content_hash(), qr/value=undef/, 'undef value in content_hash');

my $region = Chalk::IR::Node::Region->new(id => 'reg_0', inputs => []);
my $v1 = Chalk::IR::Node->new(id => 'v1');
my $v2 = Chalk::IR::Node->new(id => 'v2');
my $phi = Chalk::IR::Node::Phi->new(id => 'phi_0', region => $region, inputs => [$v1, $v2]);
is($phi->operation(), 'Phi', 'Phi operation');
is($phi->region()->id(), 'reg_0', 'Phi region');
like($phi->content_hash(), qr/Phi\|region=reg_0/, 'Phi content_hash includes region');

my $v3 = Chalk::IR::Node->new(id => 'v3');
$phi->set_backedge($v3);
is($phi->inputs()->[1]->id(), 'v3', 'Phi backedge updated');

my $pad = Chalk::IR::Node::PadAccess->new(id => 'pad_0', targ => 3, varname => '$x');
isa_ok($pad, 'Chalk::IR::Node::Access', 'PadAccess isa Access');
is($pad->operation(), 'PadAccess', 'PadAccess operation');
is($pad->targ(), 3, 'PadAccess targ');
is($pad->varname(), '$x', 'PadAccess varname');
like($pad->content_hash(), qr/PadAccess\|varname=\$x/, 'PadAccess content_hash keyed on varname, not targ');

my $fa = Chalk::IR::Node::FieldAccess->new(id => 'fa_0', field_index => 0, field_stash => 'MyClass');
isa_ok($fa, 'Chalk::IR::Node::Access', 'FieldAccess isa Access');
is($fa->operation(), 'FieldAccess', 'FieldAccess operation');
is($fa->field_index(), 0, 'FieldAccess field_index');
is($fa->field_stash(), 'MyClass', 'FieldAccess field_stash');

my $sa = Chalk::IR::Node::StashAccess->new(id => 'sa_0');
isa_ok($sa, 'Chalk::IR::Node::Access', 'StashAccess isa Access');
is($sa->operation(), 'StashAccess', 'StashAccess operation');

my $target = Chalk::IR::Node->new(id => 'tgt_0');
my $index  = Chalk::IR::Node->new(id => 'idx_0');
my $sub = Chalk::IR::Node::Subscript->new(id => 'sub_0', inputs => [$target, $index]);
isa_ok($sub, 'Chalk::IR::Node::Access', 'Subscript isa Access');
is($sub->operation(), 'Subscript', 'Subscript operation');

done_testing();
