# ABOUTME: Tests for previously-missing operator typed nodes.
# ABOUTME: Verifies Repeat, Match, NotMatch, DefinedOr, Xor, Range, Yada, IsaOp, UnaryPlus, Ref.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::Repeat;
use Chalk::IR::Node::Match;
use Chalk::IR::Node::NotMatch;
use Chalk::IR::Node::DefinedOr;
use Chalk::IR::Node::Xor;
use Chalk::IR::Node::Range;
use Chalk::IR::Node::Yada;
use Chalk::IR::Node::IsaOp;
use Chalk::IR::Node::UnaryPlus;
use Chalk::IR::Node::Ref;

my $left    = Chalk::IR::Node->new(id => 'left_0');
my $right   = Chalk::IR::Node->new(id => 'right_0');
my $operand = Chalk::IR::Node->new(id => 'operand_0');

my %binops = (
    Repeat    => 'x',
    Match     => '=~',
    NotMatch  => '!~',
    DefinedOr => '//',
    Xor       => 'xor',
    Range     => '..',
    Yada      => '...',
    IsaOp     => 'isa',
);

for my $type (sort keys %binops) {
    my $class = "Chalk::IR::Node::$type";
    my $node  = $class->new(
        id     => "${type}_test",
        inputs => [$left, $right],
        left   => $left,
        right  => $right,
    );
    isa_ok($node, 'Chalk::IR::Node::BinOp', "$type isa BinOp");
    isa_ok($node, 'Chalk::IR::Node',        "$type isa Node");
    is($node->operation(), $type,           "$type operation()");
    is($node->op_str(),    $binops{$type},  "$type op_str() is $binops{$type}");
    is($node->left()->id(),  'left_0',      "$type left() accessor");
    is($node->right()->id(), 'right_0',     "$type right() accessor");
}

my %unops = (
    UnaryPlus => '+',
    Ref       => '\\',
);

for my $type (sort keys %unops) {
    my $class = "Chalk::IR::Node::$type";
    my $node  = $class->new(
        id      => "${type}_test",
        inputs  => [$operand],
        operand => $operand,
    );
    isa_ok($node, 'Chalk::IR::Node::UnaryOp', "$type isa UnaryOp");
    isa_ok($node, 'Chalk::IR::Node',          "$type isa Node");
    is($node->operation(), $type,             "$type operation()");
    is($node->op_str(),    $unops{$type},     "$type op_str() is $unops{$type}");
    is($node->operand()->id(), 'operand_0',   "$type operand() accessor");
}

done_testing();
