# ABOUTME: Tests for Chalk::IR::Node::BinOp hierarchy.
# ABOUTME: Verifies intermediate base class accessors and all 29 leaf node types.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Power;
use Chalk::IR::Node::Concat;
use Chalk::IR::Node::NumEq;
use Chalk::IR::Node::NumNe;
use Chalk::IR::Node::NumLt;
use Chalk::IR::Node::NumGt;
use Chalk::IR::Node::NumLe;
use Chalk::IR::Node::NumGe;
use Chalk::IR::Node::NumCmp;
use Chalk::IR::Node::StrEq;
use Chalk::IR::Node::StrNe;
use Chalk::IR::Node::StrLt;
use Chalk::IR::Node::StrGt;
use Chalk::IR::Node::StrLe;
use Chalk::IR::Node::StrGe;
use Chalk::IR::Node::StrCmp;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::BitAnd;
use Chalk::IR::Node::BitOr;
use Chalk::IR::Node::BitXor;
use Chalk::IR::Node::LeftShift;
use Chalk::IR::Node::RightShift;
use Chalk::IR::Node::Assign;

my $left  = Chalk::IR::Node->new(id => 'left_0');
my $right = Chalk::IR::Node->new(id => 'right_0');

# BinOp base class accessors via Add
my $add = Chalk::IR::Node::Add->new(id => 'add_0', inputs => [$left, $right]);
isa_ok($add, 'Chalk::IR::Node::BinOp', 'Add isa BinOp');
isa_ok($add, 'Chalk::IR::Node', 'Add isa Node');
is($add->left()->id(), 'left_0', 'left() returns inputs->[0]');
is($add->right()->id(), 'right_0', 'right() returns inputs->[1]');
is($add->operation(), 'Add', 'Add operation');
is($add->op_str(), '+', 'Add op_str is +');

# content_hash includes operation name
like($add->content_hash(), qr/^Add\|/, 'Add content_hash starts with Add');

# Named left/right fields: construction with explicit named params
my $add_named = Chalk::IR::Node::Add->new(
    id     => 'add_named',
    inputs => [$left, $right],
    left   => $left,
    right  => $right,
);
is($add_named->left()->id(),  'left_0',  'named left() returns left node');
is($add_named->right()->id(), 'right_0', 'named right() returns right node');

# Migration layout: 3-element inputs [op, left, right] with named fields
my $op_const = Chalk::IR::Node->new(id => 'op_const');
my $add_migr = Chalk::IR::Node::Add->new(
    id     => 'add_migr',
    inputs => [$op_const, $left, $right],
    left   => $left,
    right  => $right,
);
is($add_migr->left()->id(),  'left_0',  'migration: left() from named field');
is($add_migr->right()->id(), 'right_0', 'migration: right() from named field');
is(scalar $add_migr->inputs()->@*, 3,   'migration: inputs has 3 elements');

# Verify all 29 leaf types: operation, op_str, isa BinOp
my %expected = (
    Add        => '+',   Subtract   => '-',   Multiply => '*',
    Divide     => '/',   Modulo     => '%',   Power    => '**',
    Concat     => '.',
    NumEq      => '==',  NumNe      => '!=',  NumLt    => '<',
    NumGt      => '>',   NumLe      => '<=',  NumGe    => '>=',
    NumCmp     => '<=>',
    StrEq      => 'eq',  StrNe      => 'ne',  StrLt    => 'lt',
    StrGt      => 'gt',  StrLe      => 'le',  StrGe    => 'ge',
    StrCmp     => 'cmp',
    And        => '&&',  Or         => '||',
    BitAnd     => '&',   BitOr      => '|',   BitXor   => '^',
    LeftShift  => '<<',  RightShift => '>>',
    Assign     => '=',
);

for my $type (sort keys %expected) {
    my $class = "Chalk::IR::Node::$type";
    my $node = $class->new(id => "${type}_test", inputs => [$left, $right]);
    isa_ok($node, 'Chalk::IR::Node::BinOp', "$type isa BinOp");
    is($node->operation(), $type, "$type operation");
    is($node->op_str(), $expected{$type}, "$type op_str is $expected{$type}");
}

done_testing();
