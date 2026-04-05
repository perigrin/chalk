# ABOUTME: Tests for Chalk::IR CFG node classes.
# ABOUTME: Verifies Start, Return, Unwind, If, Proj, Region, Loop.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Loop;

# Start
my $start = Chalk::IR::Node::Start->new(id => 'start_0');
isa_ok($start, 'Chalk::IR::Node::Start');
isa_ok($start, 'Chalk::IR::Node');
is($start->operation(), 'Start', 'Start operation');

# Return
my $val = Chalk::IR::Node->new(id => 'val_0');
my $ret = Chalk::IR::Node::Return->new(id => 'ret_0', inputs => [$start, $val]);
is($ret->operation(), 'Return', 'Return operation');
is(scalar $ret->inputs()->@*, 2, 'Return has control + value inputs');

# Unwind (exceptional exit for die)
my $exc = Chalk::IR::Node->new(id => 'exc_0');
my $unwind = Chalk::IR::Node::Unwind->new(id => 'unw_0', inputs => [$start, $exc]);
is($unwind->operation(), 'Unwind', 'Unwind operation');
isa_ok($unwind, 'Chalk::IR::Node');

# If
my $cond = Chalk::IR::Node->new(id => 'cond_0');
my $if = Chalk::IR::Node::If->new(id => 'if_0', inputs => [$start, $cond]);
is($if->operation(), 'If', 'If operation');

# Proj
my $proj = Chalk::IR::Node::Proj->new(id => 'proj_0', inputs => [$if], index => 0);
is($proj->operation(), 'Proj', 'Proj operation');
is($proj->index(), 0, 'Proj index');

# Region
my $proj2 = Chalk::IR::Node::Proj->new(id => 'proj_1', inputs => [$if], index => 1);
my $region = Chalk::IR::Node::Region->new(id => 'reg_0', inputs => [$proj, $proj2]);
is($region->operation(), 'Region', 'Region operation');

# Loop
my $loop = Chalk::IR::Node::Loop->new(id => 'loop_0', inputs => [$start, undef]);
is($loop->operation(), 'Loop', 'Loop operation');

# Loop backedge mutation
my $back = Chalk::IR::Node->new(id => 'back_0');
$loop->set_backedge_ctrl($back);
is($loop->inputs()->[1]->id(), 'back_0', 'Loop backedge set');

done_testing();
