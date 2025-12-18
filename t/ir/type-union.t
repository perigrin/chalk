# ABOUTME: Test for Union type representing multiple possible types
# ABOUTME: Used at control flow merge points (Phi nodes)

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";

use Chalk::IR::Type::Union;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

# Test 1: Union creation with multiple types
subtest 'Union creation' => sub {
    my $int = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->TOP();

    my $union = Chalk::IR::Type::Union->new(members => [$int, $float]);

    ok($union isa Chalk::IR::Type::Union, 'Union created');
    is(scalar($union->members->@*), 2, 'Union has 2 members');
};

# Test 2: Union contains check
subtest 'Union contains' => sub {
    my $int = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->TOP();
    my $union = Chalk::IR::Type::Union->new(members => [$int, $float]);

    ok($union->contains($int), 'Union contains Integer');
    ok($union->contains($float), 'Union contains Float');

    my $top = Chalk::IR::Type::Top->top();
    ok(!$union->contains($top), 'Union does not contain Top');
};

# Test 3: Union meet (intersection)
subtest 'Union meet' => sub {
    my $int = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->TOP();
    my $union1 = Chalk::IR::Type::Union->new(members => [$int, $float]);

    # Meet with one of its members narrows to that member
    my $result = $union1->meet($int);
    ok($result isa Chalk::IR::Type::Integer, 'Meet with member narrows');
};

# Test 4: Union of unions flattens
subtest 'Union flattening' => sub {
    my $int = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->TOP();
    my $union1 = Chalk::IR::Type::Union->new(members => [$int]);
    my $union2 = Chalk::IR::Type::Union->new(members => [$float]);

    my $combined = Chalk::IR::Type::Union->new(members => [$union1, $union2]);
    # Should flatten: Union(Union(Int), Union(Float)) -> Union(Int, Float)
    is(scalar($combined->members->@*), 2, 'Nested unions flatten');
};

# Test 5: is_constant returns false
subtest 'Union is not constant' => sub {
    my $const_int = Chalk::IR::Type::Integer->constant(42);
    my $const_float = Chalk::IR::Type::Float->constant(3.14);
    my $union = Chalk::IR::Type::Union->new(members => [$const_int, $const_float]);

    ok(!$union->is_constant, 'Union is never constant');
};

done_testing();
