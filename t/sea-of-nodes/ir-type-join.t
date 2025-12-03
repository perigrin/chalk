# ABOUTME: Tests for join() method on IR types (dual of meet())
# ABOUTME: join() computes least upper bound in the type lattice

use lib 'lib';
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Type;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::Integer;

subtest 'Top join semantics' => sub {
    my $top = Chalk::IR::Type::Top->top();
    my $int5 = Chalk::IR::Type::Integer->constant(5);
    my $bottom = Chalk::IR::Type::Bottom->BOTTOM();

    # Top is absorbing for join (opposite of meet)
    my $result1 = $top->join($int5);
    ok $result1 isa Chalk::IR::Type::Top, 'Top join Int = Top';

    my $result2 = $top->join($bottom);
    ok $result2 isa Chalk::IR::Type::Top, 'Top join Bottom = Top';

    my $result3 = $top->join($top);
    ok $result3 isa Chalk::IR::Type::Top, 'Top join Top = Top';
};

subtest 'Bottom join semantics' => sub {
    my $bottom = Chalk::IR::Type::Bottom->BOTTOM();
    my $int5 = Chalk::IR::Type::Integer->constant(5);
    my $top = Chalk::IR::Type::Top->top();

    # Bottom is identity for join (opposite of meet)
    my $result1 = $bottom->join($int5);
    is ref($result1), 'Chalk::IR::Type::Integer', 'Bottom join Int = Int';
    is $result1->value, 5, 'value preserved';

    my $result2 = $bottom->join($top);
    ok $result2 isa Chalk::IR::Type::Top, 'Bottom join Top = Top';

    my $result3 = $bottom->join($bottom);
    ok $result3 isa Chalk::IR::Type::Bottom, 'Bottom join Bottom = Bottom';
};

subtest 'TypeInteger join semantics' => sub {
    my $int5 = Chalk::IR::Type::Integer->constant(5);
    my $int5b = Chalk::IR::Type::Integer->constant(5);
    my $int3 = Chalk::IR::Type::Integer->constant(3);
    my $int_top = Chalk::IR::Type::Integer->TOP();
    my $int_bot = Chalk::IR::Type::Integer->BOTTOM();

    # Same constant: join = that constant
    my $result1 = $int5->join($int5b);
    ok $result1->is_constant, 'same constants join to constant';
    is $result1->value, 5, 'value is 5';

    # Different constants: join = IntTop (unknown)
    my $result2 = $int5->join($int3);
    ok $result2->is_top, 'different constants join to IntTop';

    # IntTop absorbs in join
    my $result3 = $int_top->join($int5);
    ok $result3->is_top, 'IntTop join const = IntTop';

    my $result4 = $int5->join($int_top);
    ok $result4->is_top, 'const join IntTop = IntTop';

    # IntBot is identity for join
    my $result5 = $int_bot->join($int5);
    ok $result5->is_constant, 'IntBot join const = const';
    is $result5->value, 5, 'value preserved';

    my $result6 = $int5->join($int_bot);
    ok $result6->is_constant, 'const join IntBot = const';
    is $result6->value, 5, 'value preserved';
};
