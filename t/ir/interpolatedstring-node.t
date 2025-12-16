# ABOUTME: Tests for InterpolatedString IR node
# ABOUTME: Verifies InterpolatedString node holds parts for concatenation

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::InterpolatedString;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Scalar::Util 'blessed';

# Create fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Create mock parts for testing
my $part1 = Chalk::IR::Node::Constant->new(
    value => 'Hello ',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

my $part2 = Chalk::IR::Node::Constant->new(
    value => 'name_var_placeholder',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

my $part3 = Chalk::IR::Node::Constant->new(
    value => '!',
    type => Chalk::Grammar::Chalk::Type::Str->new()
);

subtest 'InterpolatedString node basic structure' => sub {
    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2, $part3],
    );

    ok(defined($interp), 'InterpolatedString node is defined');
    ok(blessed($interp), 'InterpolatedString node is blessed');
    ok($interp->isa('Chalk::IR::Node::InterpolatedString'), 'InterpolatedString node has correct type');
};

subtest 'InterpolatedString node op method' => sub {
    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2],
    );

    is($interp->op(), 'InterpolatedString', 'op() returns InterpolatedString');
};

subtest 'InterpolatedString node accessors' => sub {
    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2, $part3],
    );

    ok(defined($interp->parts), 'parts accessor works');
    is(ref($interp->parts), 'ARRAY', 'parts is arrayref');
    is(scalar(@{$interp->parts}), 3, 'parts has 3 elements');
    is($interp->parts->[0]->id, $part1->id, 'first part is correct');
    is($interp->parts->[1]->id, $part2->id, 'second part is correct');
    is($interp->parts->[2]->id, $part3->id, 'third part is correct');
};

subtest 'InterpolatedString node to_hash' => sub {
    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2],
    );

    my $hash = $interp->to_hash();
    is($hash->{op}, 'InterpolatedString', 'to_hash op is InterpolatedString');
    is($hash->{id}, $interp->id, 'to_hash id matches');
    ok(defined($hash->{attributes}), 'to_hash has attributes');
    ok(defined($hash->{attributes}{part_ids}), 'attributes has part_ids');
    is(ref($hash->{attributes}{part_ids}), 'ARRAY', 'part_ids is arrayref');
};

subtest 'InterpolatedString node inputs' => sub {
    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2, $part3],
    );

    my $inputs = $interp->inputs();
    ok(ref($inputs) eq 'ARRAY', 'inputs returns arrayref');
    is(scalar(@$inputs), 3, 'inputs has 3 elements');
    is($inputs->[0], $part1->id, 'First input is part1 id');
    is($inputs->[1], $part2->id, 'Second input is part2 id');
    is($inputs->[2], $part3->id, 'Third input is part3 id');
};

done_testing();
