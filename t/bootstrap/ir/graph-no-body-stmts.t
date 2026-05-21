# ABOUTME: Asserts Chalk::IR::Graph no longer has a body_stmts field.
# ABOUTME: Per Phase 7, body_stmts seeding is replaced by per-class hash-cons reachability.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Graph;

ok(!Chalk::IR::Graph->can('body_stmts'),
    'Graph no longer exposes body_stmts() reader');

# Constructor should not accept body_stmts as a parameter.
# (Even if it did, we want the field gone — :param requires a field.)
my $g = eval { Chalk::IR::Graph->new(body_stmts => [1, 2, 3]) };
my $err = $@;
ok($err, 'constructor rejects unknown body_stmts param')
    or diag("Graph still accepts body_stmts: " . ($g // 'undef'));

# Source code itself should not declare a body_stmts field.
my $graph_pm = do {
    open my $fh, '<', 'lib/Chalk/IR/Graph.pm' or die "$!";
    local $/;
    <$fh>;
};
unlike($graph_pm, qr/\bfield\s+\$body_stmts\b/,
    'Graph.pm has no field $body_stmts declaration');
unlike($graph_pm, qr/\bbody_stmts\s*=>/,
    'Graph.pm has no body_stmts hash usage');

done_testing();
