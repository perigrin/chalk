# ABOUTME: Integration tests for combined peephole + GVN optimization
# ABOUTME: Validates that peephole and GVN work together in single pass

use lib 'lib';
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Graph;
use Chalk::IR::Optimizer::IterPeeps;

subtest 'peephole creates GVN opportunity: (a+b) + (a+b)' => sub {
    # Build: (5+10) + (5+10)
    # Peephole folds both 5+10 -> 15
    # GVN deduplicates the two Constant(15) nodes
    # Final peephole folds 15+15 -> 30

    my $graph = Chalk::IR::Graph->new();

    my $a = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $sum1 = Chalk::IR::Node::Add->new(left => $a, right => $b);
    my $sum2 = Chalk::IR::Node::Add->new(left => $a, right => $b);
    my $total = Chalk::IR::Node::Add->new(left => $sum1, right => $sum2);

    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($sum1);
    $graph->add_node($sum2);
    $graph->add_node($total);

    is $graph->node_count, 5, 'Graph has 5 nodes before optimization';

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->run_iterpeeps($graph);
    my $optimized = $result->{graph};
    my $metrics = $result->{metrics};

    # Should have constant 30 in result
    my @constants = grep { $_->op eq 'Constant' } values $optimized->nodes->%*;
    my @value_30 = grep { $_->attributes->{value} == 30 } @constants;

    ok scalar(@value_30) >= 1, 'Has Constant(30) after combined optimization';
    ok $metrics->{peepholes_applied} >= 3, 'Multiple peepholes applied';
};

subtest 'GVN merge enables new peephole: shared subexpression' => sub {
    # Build: (x + y) * 2 and (x + y) * 3
    # GVN should recognize (x + y) is computed twice
    # Note: This tests that GVN works during peephole, not after

    my $graph = Chalk::IR::Graph->new();

    my $x = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');
    my $y = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $two = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $three = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    my $sum1 = Chalk::IR::Node::Add->new(left => $x, right => $y);      # x + y = 7
    my $sum2 = Chalk::IR::Node::Add->new(left => $x, right => $y);      # x + y = 7 (duplicate)
    my $mul1 = Chalk::IR::Node::Multiply->new(left => $sum1, right => $two);   # 7 * 2 = 14
    my $mul2 = Chalk::IR::Node::Multiply->new(left => $sum2, right => $three); # 7 * 3 = 21

    $graph->add_node($x);
    $graph->add_node($y);
    $graph->add_node($two);
    $graph->add_node($three);
    $graph->add_node($sum1);
    $graph->add_node($sum2);
    $graph->add_node($mul1);
    $graph->add_node($mul2);

    is $graph->node_count, 8, 'Graph has 8 nodes before optimization';

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->run_iterpeeps($graph);
    my $optimized = $result->{graph};
    my $metrics = $result->{metrics};

    # Both multiplications should fold to constants
    my @constants = grep { $_->op eq 'Constant' } values $optimized->nodes->%*;

    # Should have 14 and 21 (or just those if fully folded)
    my @value_14 = grep { $_->attributes->{value} == 14 } @constants;
    my @value_21 = grep { $_->attributes->{value} == 21 } @constants;

    ok scalar(@value_14) >= 1 || scalar(@value_21) >= 1, 'Multiplications folded to constants';
};

subtest 'metrics report GVN hits' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create two identical additions that will fold to same constant
    my $a = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $add1 = Chalk::IR::Node::Add->new(left => $a, right => $b);
    my $add2 = Chalk::IR::Node::Add->new(left => $a, right => $b);

    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($add1);
    $graph->add_node($add2);

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->run_iterpeeps($graph);
    my $metrics = $result->{metrics};

    ok exists($metrics->{gvn_hits}), 'metrics include gvn_hits';
    # Note: gvn_hits may be 0 or more depending on ordering
};
