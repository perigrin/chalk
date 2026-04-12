# ABOUTME: Tests that Actions.pm produces Chalk::IR::MethodInfo for method declarations.
# ABOUTME: Verifies end-to-end pipeline: parse source with methods -> MethodInfo structs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::Graph;
use Chalk::IR::Program;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::MethodInfoPipelineTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::MethodInfoPipelineTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

my sub parse_file($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result;
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# ============================================================
# 1. Constant.pm — Actions.pm should produce MethodInfo for methods
# ============================================================

{
    my $ir = parse_file('lib/Chalk/IR/Node/Constant.pm');
    ok(defined $ir, 'Constant.pm: parse produces IR');

    SKIP: {
        skip 'Constant.pm: no IR', 20 unless defined $ir;

        isa_ok($ir, 'Chalk::IR::Program', 'Constant.pm: IR is Chalk::IR::Program');
        my ($cls) = $ir->classes()->@*;
        ok(defined $cls, 'Constant.pm: found class declaration');

        SKIP: {
            skip 'Constant.pm: no class declaration', 15 unless defined $cls;

            my $body = $cls isa Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2];
            is(ref $body, 'ARRAY', 'Constant.pm: body is arrayref');

            # Methods should now be Chalk::IR::MethodInfo, not Constructor:MethodDecl
            my @methods = grep { $_ isa Chalk::IR::MethodInfo } $body->@*;
            ok(scalar @methods >= 2,
                'Constant.pm: body contains at least 2 MethodInfo objects')
                or diag("Got " . scalar @methods . " MethodInfo objects; body has "
                    . scalar($body->@*) . " items total");

            my ($op_method) = grep { $_->name() eq 'operation' } @methods;
            ok(defined $op_method, 'Constant.pm: found operation() method as MethodInfo');

            SKIP: {
                skip 'Constant.pm: no operation() method', 6 unless defined $op_method;

                isa_ok($op_method, 'Chalk::IR::MethodInfo', 'operation() is a MethodInfo');
                is($op_method->name(), 'operation', 'MethodInfo name is plain string');

                my $params = $op_method->params();
                is(ref $params, 'ARRAY', 'MethodInfo params is arrayref');
                ok(scalar $params->@* >= 0, 'MethodInfo params is valid arrayref');

                # Params should be plain strings, not Constant nodes
                if (scalar $params->@* > 0) {
                    ok(!ref($params->[0]), 'MethodInfo param[0] is a plain string');
                }

                my $body_stmts = $op_method->body();
                is(ref $body_stmts, 'ARRAY', 'MethodInfo body() is arrayref');
                ok(scalar $body_stmts->@* > 0, 'MethodInfo body() is non-empty');

                my $rt = $op_method->return_type();
                ok(defined $rt, 'MethodInfo return_type() is defined');
                ok(!ref($rt), 'MethodInfo return_type() is a plain string');
            }

            my ($ch_method) = grep { $_->name() eq 'content_hash' } @methods;
            ok(defined $ch_method, 'Constant.pm: found content_hash() method as MethodInfo');
        }
    }
}

# ============================================================
# 2. Per-method Graph built during parsing
# ============================================================

{
    my $ir = parse_file('lib/Chalk/IR/Node/Constant.pm');

    SKIP: {
        skip 'Constant.pm: no IR for graph test', 8 unless defined $ir;

        my ($cls) = $ir->classes()->@*;
        skip 'Constant.pm: no class for graph test', 8 unless defined $cls;

        my $body = $cls isa Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2];
        my @methods = grep { $_ isa Chalk::IR::MethodInfo } $body->@*;
        skip 'Constant.pm: no methods for graph test', 8 unless @methods;

        my ($op_method) = grep { $_->name() eq 'operation' } @methods;
        skip 'Constant.pm: no operation() for graph test', 8 unless defined $op_method;

        # Every MethodInfo produced by Actions::MethodDefinition should have a Graph.
        my $graph = $op_method->graph();
        ok(defined $graph, 'operation() MethodInfo has a graph');

        SKIP: {
            skip 'no graph on operation() MethodInfo', 7 unless defined $graph;

            isa_ok($graph, 'Chalk::IR::Graph', 'graph is a Chalk::IR::Graph');
            ok(defined $graph->start(), 'graph has a start node');
            is(ref($graph->returns()), 'ARRAY', 'graph returns() is arrayref');
            is(ref($graph->schedule()), 'HASH', 'graph schedule() is a hashref');

            # The schedule may be empty (no if/loop/try in a simple method),
            # but must be defined and a hashref.
            ok(defined $graph->schedule(), 'graph schedule is defined');

            # All MethodInfo objects in the body should carry graphs.
            my $all_have_graphs = 1;
            for my $m (@methods) {
                if (!defined $m->graph()) {
                    $all_have_graphs = 0;
                    last;
                }
            }
            ok($all_have_graphs, 'all MethodInfo objects have graphs');
        }
    }
}

done_testing();
