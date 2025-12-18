# ABOUTME: Test that comparison operators return Bool type
# ABOUTME: Part of type inference for expressions (#370)

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::GT;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::EQ;
use Chalk::IR::Node::NE;
use Chalk::IR::Node::GE;
use Chalk::IR::Node::LE;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Bool;

# Create test constants
my $const5 = Chalk::IR::Node::Constant->new(
    value => 5,
    type => Chalk::IR::Type::Integer->constant(5),
);
my $const3 = Chalk::IR::Node::Constant->new(
    value => 3,
    type => Chalk::IR::Type::Integer->constant(3),
);

# Test: GT returns Bool
subtest 'GT compute_type returns Bool' => sub {
    my $gt = Chalk::IR::Node::GT->new(left => $const5, right => $const3);
    ok($gt->can('compute_type'), 'GT has compute_type');
    my $type = $gt->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'GT returns Bool type');
};

# Test: LT returns Bool
subtest 'LT compute_type returns Bool' => sub {
    my $lt = Chalk::IR::Node::LT->new(left => $const5, right => $const3);
    my $type = $lt->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'LT returns Bool type');
};

# Test: EQ returns Bool
subtest 'EQ compute_type returns Bool' => sub {
    my $eq = Chalk::IR::Node::EQ->new(left => $const5, right => $const3);
    my $type = $eq->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'EQ returns Bool type');
};

# Test: NE returns Bool
subtest 'NE compute_type returns Bool' => sub {
    my $ne = Chalk::IR::Node::NE->new(left => $const5, right => $const3);
    my $type = $ne->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'NE returns Bool type');
};

# Test: GE returns Bool
subtest 'GE compute_type returns Bool' => sub {
    my $ge = Chalk::IR::Node::GE->new(left => $const5, right => $const3);
    my $type = $ge->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'GE returns Bool type');
};

# Test: LE returns Bool
subtest 'LE compute_type returns Bool' => sub {
    my $le = Chalk::IR::Node::LE->new(left => $const5, right => $const3);
    my $type = $le->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'LE returns Bool type');
};

done_testing();
