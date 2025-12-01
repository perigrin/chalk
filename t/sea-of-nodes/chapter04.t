# ABOUTME: Test for Sea of Nodes IR generation - Chapter 4: Bool, Tuple, @ARGV
# ABOUTME: Validates TypeBool, TypeTuple, Start as MultiNode, and $arg binding

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(refaddr);
use builtin qw(true false is_bool);

use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Proj');
use_ok('Chalk::IR::Type::TypeTuple');
use_ok('Chalk::IR::Type::TypeCtrl');
use_ok('Chalk::IR::Type::TypeInteger');
use_ok('Chalk::IR::Type::Top');

subtest 'Start is_multi() returns true' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    ok($start->can('is_multi'), 'Start has is_multi() method');
    ok($start->is_multi, 'Start is_multi() returns true');
};

subtest 'Start compute() returns TypeTuple' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    my $type = $start->compute();
    ok($type isa Chalk::IR::Type::TypeTuple, 'Start compute() returns TypeTuple');
};

subtest 'Start compute() tuple has (ctrl, arg)' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main', arg_value => 42);

    my $type = $start->compute();

    my $ctrl_type = $type->at(0);
    ok($ctrl_type isa Chalk::IR::Type::TypeCtrl, 'Tuple[0] is TypeCtrl');

    my $arg_type = $type->at(1);
    ok($arg_type isa Chalk::IR::Type::TypeInteger, 'Tuple[1] is TypeInteger');
    is($arg_type->value, 42, 'Tuple[1] value is 42');
};

subtest 'Start compute() with no arg returns Top for arg' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    my $type = $start->compute();

    my $arg_type = $type->at(1);
    ok($arg_type isa Chalk::IR::Type::Top, 'Tuple[1] is Top when no arg');
};

done_testing();
