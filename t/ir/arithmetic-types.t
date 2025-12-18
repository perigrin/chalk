# ABOUTME: Test type inference for arithmetic operations
# ABOUTME: Part of Operation Type Preservation (#370)

use v5.42;
use Test::More;

use FindBin;
use lib "$FindBin::Bin/../../lib";

use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

my $int5 = Chalk::IR::Node::Constant->new(
    value => 5, type => Chalk::IR::Type::Integer->constant(5));
my $int3 = Chalk::IR::Node::Constant->new(
    value => 3, type => Chalk::IR::Type::Integer->constant(3));
my $float2 = Chalk::IR::Node::Constant->new(
    value => 2.0, type => Chalk::IR::Type::Float->constant(2.0));

# Test: Subtract int - int = int
subtest 'Subtract int-int returns Integer' => sub {
    my $sub = Chalk::IR::Node::Subtract->new(left => $int5, right => $int3);
    ok($sub->can('compute_type'), 'Subtract has compute_type');
    my $type = $sub->compute_type;
    ok($type isa Chalk::IR::Type::Integer, 'Int - Int = Integer');
};

# Test: Divide (always returns Float for safety)
subtest 'Divide returns Float' => sub {
    my $div = Chalk::IR::Node::Divide->new(left => $int5, right => $int3);
    my $type = $div->compute_type;
    ok($type isa Chalk::IR::Type::Float, 'Divide returns Float');
};

# Test: Negate preserves type
subtest 'Negate preserves operand type' => sub {
    my $neg = Chalk::IR::Node::Negate->new(operand => $int5);
    my $type = $neg->compute_type;
    ok($type isa Chalk::IR::Type::Integer, 'Negate Int = Integer');
};

done_testing();
