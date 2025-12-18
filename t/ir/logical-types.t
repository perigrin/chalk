# ABOUTME: Test type inference for logical operations
# ABOUTME: Part of Operation Type Preservation (#370)

use v5.42;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Test::More;

use Chalk::IR::Node::Not;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Bool;

my $int5 = Chalk::IR::Node::Constant->new(
    value => 5, type => Chalk::IR::Type::Integer->constant(5));

# Test: Not returns Bool
subtest 'Not returns Bool' => sub {
    my $not = Chalk::IR::Node::Not->new(operand => $int5);
    ok($not->can('compute_type'), 'Not has compute_type');
    my $type = $not->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'Not returns Bool');
};

done_testing();
