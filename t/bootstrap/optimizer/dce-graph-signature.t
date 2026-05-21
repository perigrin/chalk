# ABOUTME: Tests that DCE::run accepts a Chalk::IR::Graph and returns one.
# ABOUTME: Per Phase 5, the pass contract is run($X) -> $X at the same scope.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::Bootstrap::Optimizer::DCE;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;

ok(Chalk::Bootstrap::Optimizer::DCE->can('run'),
    'DCE has run method');

# Empty graph in, graph out.
{
    my $graph   = Chalk::IR::Graph->new;
    my $factory = Chalk::IR::NodeFactory->new;
    my $dce     = Chalk::Bootstrap::Optimizer::DCE->new;
    my $out     = $dce->run($graph, $factory);

    ok(defined $out, 'run(graph) returns a defined value');
    ok(blessed($out) && $out isa Chalk::IR::Graph,
        'run(graph) returns a Chalk::IR::Graph')
        or diag('got: ' . (defined $out ? ref($out) : 'undef'));
}

# Graph with one merged node: run preserves the live node.
{
    my $graph   = Chalk::IR::Graph->new;
    my $factory = Chalk::IR::NodeFactory->new;
    my $live = Chalk::IR::Node::Constant->new(
        id         => 'live',
        value      => 42,
        const_type => 'integer',
    );
    $graph->merge($live);

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new;
    my $out = $dce->run($graph, $factory);
    ok(defined $out && $out isa Chalk::IR::Graph,
        'run(graph-with-live) returns a graph');
}

done_testing();
