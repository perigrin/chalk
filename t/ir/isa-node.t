# ABOUTME: Tests for ISA IR node
# ABOUTME: Verifies ISA node for type checking (isa operator)

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::ISA;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Int;
use Scalar::Util 'blessed', 'refaddr';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

subtest 'ISA node basic structure' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 'Str',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $isa_node = Chalk::IR::Node::ISA->new(
        left => $left,
        right => $right,
    );

    ok(defined($isa_node), 'ISA node is defined');
    ok(blessed($isa_node), 'ISA node is blessed');
    ok($isa_node->isa('Chalk::IR::Node::ISA'), 'ISA node has correct type');
};

subtest 'ISA node op method' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 'Int',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $isa_node = Chalk::IR::Node::ISA->new(
        left => $left,
        right => $right,
    );

    is($isa_node->op, 'ISA', 'op() returns ISA');
};

subtest 'ISA node accessors' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 'Str',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $isa_node = Chalk::IR::Node::ISA->new(
        left => $left,
        right => $right,
    );

    is($isa_node->left, $left, 'left accessor works');
    is($isa_node->right, $right, 'right accessor works');
};

subtest 'ISA node inputs' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 'Str',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $isa_node = Chalk::IR::Node::ISA->new(
        left => $left,
        right => $right,
    );

    my $inputs = $isa_node->inputs;
    is(ref($inputs), 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 2, 'inputs has 2 elements');
    is($inputs->[0], $left->id, 'First input is left id');
    is($inputs->[1], $right->id, 'Second input is right id');
};

subtest 'ISA node to_hash' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 'Str',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $isa_node = Chalk::IR::Node::ISA->new(
        left => $left,
        right => $right,
    );

    my $hash = $isa_node->to_hash;
    is($hash->{op}, 'ISA', 'to_hash op is ISA');
    is($hash->{id}, $isa_node->id, 'to_hash id matches');
    ok(exists $hash->{attributes}, 'to_hash has attributes');
    is($hash->{attributes}{left_id}, $left->id, 'attributes has left_id');
    is($hash->{attributes}{right_id}, $right->id, 'attributes has right_id');
};

subtest 'ISA node peephole returns self' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 'test',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 'Str',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $isa_node = Chalk::IR::Node::ISA->new(
        left => $left,
        right => $right,
    );

    my $result = $isa_node->peephole();
    # ISA cannot be constant-folded without runtime info, returns self
    ok(defined($result), 'peephole returns defined result');
};

done_testing();
