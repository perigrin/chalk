# ABOUTME: Prototype test for control-flow threading in _build_method_graph.
# ABOUTME: Verifies that body statements are reachable via graph->nodes() for set_backedge_ctrl.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::Graph;
use Chalk::IR::Program;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Assign;

# Build Perl grammar pipeline once
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CtrlThreadTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::CtrlThreadTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

my sub parse_file($file) {
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    return $result->extract();
}

# ============================================================
# Parse Loop.pm and find set_backedge_ctrl method
# ============================================================

my $ir = parse_file('lib/Chalk/IR/Node/Loop.pm');
ok(defined $ir, 'Loop.pm: parse produces IR');

SKIP: {
    skip 'Loop.pm: no IR', 20 unless defined $ir;

    isa_ok($ir, 'Chalk::IR::Program', 'Loop.pm: IR is Chalk::IR::Program');

    my ($cls) = $ir->classes()->@*;
    ok(defined $cls, 'Loop.pm: found class declaration');

    SKIP: {
        skip 'Loop.pm: no class', 16 unless defined $cls;

        my $body = $cls isa Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2];
        is(ref $body, 'ARRAY', 'Loop.pm: body is arrayref');

        my @methods = grep { $_ isa Chalk::IR::MethodInfo } $body->@*;
        ok(scalar @methods >= 1, 'Loop.pm: has at least one method')
            or diag("Found " . scalar @methods . " methods in body of " . scalar($body->@*) . " items");

        my ($sbc) = grep { $_->name() eq 'set_backedge_ctrl' } @methods;
        ok(defined $sbc, 'Loop.pm: found set_backedge_ctrl method');

        SKIP: {
            skip 'set_backedge_ctrl not found', 12 unless defined $sbc;

            # Every MethodInfo should have a graph
            my $graph = $sbc->graph();
            ok(defined $graph, 'set_backedge_ctrl: MethodInfo has a graph');

            SKIP: {
                skip 'no graph on set_backedge_ctrl', 11 unless defined $graph;

                isa_ok($graph, 'Chalk::IR::Graph', 'graph is a Chalk::IR::Graph');

                my $nodes = $graph->nodes();
                is(ref $nodes, 'ARRAY', 'nodes() returns arrayref');

                my %ops;
                for my $node ($nodes->@*) {
                    $ops{ $node->operation() }++;
                }

                diag("Graph node operations: " . join(', ', map { "$_=$ops{$_}" } sort keys %ops));
                diag("Graph has " . scalar($nodes->@*) . " nodes total");

                # ============================================================
                # FAILING assertions: body statements not yet in graph
                #
                # The body of set_backedge_ctrl is:
                #   my $old = $self->inputs()->[1];       <- VarDecl + Assign + Call
                #   $old->remove_consumer($self) if ...;  <- Call (remove_consumer)
                #   $self->inputs()->[1] = $ctrl;         <- Assign (or Call)
                #   $ctrl->add_consumer($self) if ...;    <- Call (add_consumer)
                # ============================================================

                # 1. VarDecl for $old should be in the graph
                my @vardecls = grep { $_->operation() eq 'VarDecl' } $nodes->@*;
                ok(scalar @vardecls >= 1,
                    'graph nodes() contains VarDecl for $old')
                    or diag("No VarDecl found in graph nodes");

                # 2. Call for remove_consumer should be in the graph
                my @calls = grep { $_->operation() eq 'Call' } $nodes->@*;
                ok(scalar @calls >= 1,
                    'graph nodes() contains at least one Call node')
                    or diag("No Call nodes found in graph");

                # For method calls, the Call node's name() field holds the method name directly.
                my @remove_calls = grep {
                    $_->operation() eq 'Call'
                    && $_->can('name')
                    && defined $_->name()
                    && $_->name() =~ /remove_consumer/;
                } $nodes->@*;
                ok(scalar @remove_calls >= 1,
                    'graph nodes() contains remove_consumer call')
                    or diag("No remove_consumer call in graph (all call names: "
                        . join(', ', map { $_->can('name') ? ($_->name() // '?') : '?' } @calls)
                        . ")");

                # 3. Assign node for $self->inputs()->[1] = $ctrl should be in the graph
                my @assigns = grep { $_->operation() eq 'Assign' } $nodes->@*;
                ok(scalar @assigns >= 1,
                    'graph nodes() contains Assign node')
                    or diag("No Assign found in graph");

                # 4. Call for add_consumer should be in the graph
                my @add_calls = grep {
                    $_->operation() eq 'Call'
                    && $_->can('name')
                    && defined $_->name()
                    && $_->name() =~ /add_consumer/;
                } $nodes->@*;
                ok(scalar @add_calls >= 1,
                    'graph nodes() contains add_consumer call')
                    or diag("No add_consumer call in graph (all call names: "
                        . join(', ', map { $_->can('name') ? ($_->name() // '?') : '?' } @calls)
                        . ")");

                # 5. All 4 types of "interior" statements should appear
                note("Current node count: " . scalar($nodes->@*));
                note("B::SoN produces 19 nodes; we expect more than 6 after threading");
                ok(scalar($nodes->@*) > 6,
                    'graph has more nodes than the trivial 6-node skeleton')
                    or diag("Still only " . scalar($nodes->@*) . " nodes (Start+Constant+Call+If+Return expected to be joined by interior stmts)");
            }
        }
    }
}

done_testing();
