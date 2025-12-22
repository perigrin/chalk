# ABOUTME: Tests for List IR node
# ABOUTME: Verifies List node for holding multiple expression values

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Node::List;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Str;
use Scalar::Util 'blessed';

subtest 'List node basic structure' => sub {
    my $elem1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $elem2 = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $list = Chalk::IR::Node::List->new(
        inputs => [],
        elements => [$elem1, $elem2],
    );

    ok(defined($list), 'List node is defined');
    ok(blessed($list), 'List node is blessed');
    ok($list->isa('Chalk::IR::Node::List'), 'List node has correct type');
};

subtest 'List node op method' => sub {
    my $list = Chalk::IR::Node::List->new(
        inputs => [],
        elements => [],
    );

    is($list->op, 'List', 'op() returns List');
};

subtest 'List node elements accessor' => sub {
    my $elem1 = Chalk::IR::Node::Constant->new(
        value => 'a',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $elem2 = Chalk::IR::Node::Constant->new(
        value => 'b',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
    my $elem3 = Chalk::IR::Node::Constant->new(
        value => 'c',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $list = Chalk::IR::Node::List->new(
        inputs => [],
        elements => [$elem1, $elem2, $elem3],
    );

    is($list->length, 3, 'length returns correct count');
    is($list->element_at(0), $elem1, 'element_at(0) returns first element');
    is($list->element_at(1), $elem2, 'element_at(1) returns second element');
    is($list->element_at(2), $elem3, 'element_at(2) returns third element');
};

subtest 'List node to_hash' => sub {
    my $elem1 = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $elem2 = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $list = Chalk::IR::Node::List->new(
        inputs => [],
        elements => [$elem1, $elem2],
    );

    my $hash = $list->to_hash;
    is($hash->{op}, 'List', 'to_hash op is List');
    is($hash->{id}, $list->id, 'to_hash id matches');
    ok(exists $hash->{attributes}, 'to_hash has attributes');
    is($hash->{attributes}{element_count}, 2, 'attributes has element_count');
    is_deeply($hash->{attributes}{element_ids}, [$elem1->id, $elem2->id],
              'attributes has element_ids');
};

subtest 'List node execute evaluates elements' => sub {
    my $elem1 = Chalk::IR::Node::Constant->new(
        value => 100,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $elem2 = Chalk::IR::Node::Constant->new(
        value => 200,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $elem3 = Chalk::IR::Node::Constant->new(
        value => 300,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $list = Chalk::IR::Node::List->new(
        inputs => [],
        elements => [$elem1, $elem2, $elem3],
    );

    # Create mock context
    my %node_values = (
        $elem1->id => 100,
        $elem2->id => 200,
        $elem3->id => 300,
    );
    my $context = sub ($key) {
        if ($key =~ /^node:(.+)$/) {
            return $node_values{$1};
        }
        return undef;
    };

    my $result = $list->execute($context);
    is(ref($result), 'ARRAY', 'execute returns arrayref');
    is_deeply($result, [100, 200, 300], 'execute returns evaluated elements');
};

subtest 'Empty list' => sub {
    my $list = Chalk::IR::Node::List->new(
        inputs => [],
        elements => [],
    );

    is($list->length, 0, 'empty list has length 0');

    my $context = sub { undef };
    my $result = $list->execute($context);
    is_deeply($result, [], 'execute returns empty array for empty list');
};

done_testing();
