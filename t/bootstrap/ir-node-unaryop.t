# ABOUTME: Tests for Chalk::IR::Node::UnaryOp hierarchy.
# ABOUTME: Verifies intermediate base class accessors and all 4 leaf node types.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Complement;
use Chalk::IR::Node::Defined;

my $operand = Chalk::IR::Node->new(id => 'op_0');

my $not = Chalk::IR::Node::Not->new(id => 'not_0', inputs => [$operand]);
isa_ok($not, 'Chalk::IR::Node::UnaryOp', 'Not isa UnaryOp');
isa_ok($not, 'Chalk::IR::Node', 'Not isa Node');
is($not->operand()->id(), 'op_0', 'operand() returns inputs->[0]');
is($not->operation(), 'Not', 'Not operation');
is($not->op_str(), '!', 'Not op_str is !');

# content_hash includes operation name
like($not->content_hash(), qr/^Not\|/, 'Not content_hash starts with Not');

my %expected = (Not => '!', Negate => '-', Complement => '~', Defined => 'defined');
for my $type (sort keys %expected) {
    my $class = "Chalk::IR::Node::$type";
    my $node = $class->new(id => "${type}_test", inputs => [$operand]);
    isa_ok($node, 'Chalk::IR::Node::UnaryOp', "$type isa UnaryOp");
    is($node->operation(), $type, "$type operation");
    is($node->op_str(), $expected{$type}, "$type op_str");
}

done_testing();
