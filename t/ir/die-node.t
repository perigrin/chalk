# ABOUTME: Tests for Die IR node
# ABOUTME: Verifies Die node structure and behavior for exception handling

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Die;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Start;
use Chalk::Grammar::Chalk::Type::Str;
use Scalar::Util 'blessed', 'refaddr';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

subtest 'Die node basic structure' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $message = Chalk::IR::Node::Constant->new(
        value => 'test error',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $die_node = Chalk::IR::Node::Die->new(
        control => $start,
        message => $message,
    );

    ok(defined($die_node), 'Die node is defined');
    ok(blessed($die_node), 'Die node is blessed');
    ok($die_node->isa('Chalk::IR::Node::Die'), 'Die node has correct type');
    ok($die_node->isa('Chalk::IR::Node::CFGNode'), 'Die inherits from CFGNode');
};

subtest 'Die node op method' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $message = Chalk::IR::Node::Constant->new(
        value => 'error',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $die_node = Chalk::IR::Node::Die->new(
        control => $start,
        message => $message,
    );

    is($die_node->op, 'Die', 'op() returns Die');
};

subtest 'Die node accessors' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $message = Chalk::IR::Node::Constant->new(
        value => 'error message',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $die_node = Chalk::IR::Node::Die->new(
        control => $start,
        message => $message,
    );

    is($die_node->control, $start, 'control accessor works');
    is($die_node->message, $message, 'message accessor works');
};

subtest 'Die node inputs' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $message = Chalk::IR::Node::Constant->new(
        value => 'error',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $die_node = Chalk::IR::Node::Die->new(
        control => $start,
        message => $message,
    );

    my $inputs = $die_node->inputs;
    is(ref($inputs), 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 2, 'inputs has 2 elements (control and message)');
    is($inputs->[0], $start->id, 'First input is control id');
    is($inputs->[1], $message->id, 'Second input is message id');
};

subtest 'Die node to_hash' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $message = Chalk::IR::Node::Constant->new(
        value => 'error',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $die_node = Chalk::IR::Node::Die->new(
        control => $start,
        message => $message,
    );

    my $hash = $die_node->to_hash;
    is($hash->{op}, 'Die', 'to_hash op is Die');
    is($hash->{id}, $die_node->id, 'to_hash id matches');
    ok(exists $hash->{attributes}, 'to_hash has attributes');
    is($hash->{attributes}{control_id}, $start->id, 'attributes has control_id');
    is($hash->{attributes}{message_id}, $message->id, 'attributes has message_id');
};

subtest 'Die node isCFG' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $message = Chalk::IR::Node::Constant->new(
        value => 'error',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $die_node = Chalk::IR::Node::Die->new(
        control => $start,
        message => $message,
    );

    ok($die_node->isCFG, 'Die is a CFG node');
};

subtest 'Die node peephole returns self' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $message = Chalk::IR::Node::Constant->new(
        value => 'error',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $die_node = Chalk::IR::Node::Die->new(
        control => $start,
        message => $message,
    );

    my $result = $die_node->peephole();
    is(refaddr($result), refaddr($die_node), 'peephole returns self');
};

subtest 'Die node with_control' => sub {
    my $start1 = Chalk::IR::Node::Start->new(label => 'test1');
    my $start2 = Chalk::IR::Node::Start->new(label => 'test2');
    my $message = Chalk::IR::Node::Constant->new(
        value => 'error',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $die_node = Chalk::IR::Node::Die->new(
        control => $start1,
        message => $message,
    );

    my $rewired = $die_node->with_control($start2);
    isnt(refaddr($rewired), refaddr($die_node), 'with_control creates new node');
    is($rewired->control, $start2, 'with_control changes control');
    is($rewired->message, $message, 'with_control preserves message');
};

done_testing();
