# ABOUTME: Tests that _build_method_graph generates an implicit Return node
# ABOUTME: when the method body ends without an explicit return statement.
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
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::IR::Program;

# Build Perl grammar pipeline once
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ImplicitReturnTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::ImplicitReturnTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

my sub parse_source($source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;
    return $result->extract();
}

# ============================================================
# 1. Constant.pm - operation() method has no explicit return
#    The method body is just 'Add' — an implicit return of a string constant.
# ============================================================

{
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    open my $fh, '<:utf8', 'lib/Chalk/IR/Node/Constant.pm'
        or BAIL_OUT("Cannot read Constant.pm: $!");
    local $/;
    my $source = <$fh>;
    close $fh;

    my $result = $parser->parse_value($source);
    ok(defined $result, 'Constant.pm parses');

    SKIP: {
        skip 'Constant.pm: no parse result', 12 unless defined $result;

        my $ir = $result->extract();
        ok(defined $ir, 'Constant.pm: extract produces IR');

        SKIP: {
            skip 'Constant.pm: no IR', 11 unless defined $ir;

            isa_ok($ir, 'Chalk::IR::Program', 'IR is a Program');

            my ($cls) = $ir->classes()->@*;
            ok(defined $cls, 'found class declaration');

            SKIP: {
                skip 'no class', 8 unless defined $cls;

                my $body = $cls isa Chalk::IR::ClassInfo
                    ? $cls->body()
                    : $cls->inputs()->[2];

                my @methods = grep { $_ isa Chalk::IR::MethodInfo } $body->@*;
                ok(scalar @methods >= 1, 'found at least one MethodInfo');

                my ($op_method) = grep { $_->name() eq 'operation' } @methods;
                ok(defined $op_method, 'found operation() method');

                SKIP: {
                    skip 'no operation() method', 6 unless defined $op_method;

                    my $graph = $op_method->graph();
                    ok(defined $graph, 'operation() has a graph');

                    SKIP: {
                        skip 'no graph', 5 unless defined $graph;

                        isa_ok($graph, 'Chalk::IR::Graph', 'graph isa Chalk::IR::Graph');

                        my $returns = $graph->returns();
                        is(ref $returns, 'ARRAY', 'returns() is arrayref');

                        # THE CRITICAL ASSERTION: implicit return must be non-empty
                        ok(scalar $returns->@* > 0,
                            'operation() graph has at least one Return node (implicit return)')
                            or diag("returns is empty — implicit-return handling missing");

                        SKIP: {
                            skip 'no return nodes', 2 unless scalar $returns->@* > 0;

                            my ($ret_node) = $returns->@*;
                            isa_ok($ret_node, 'Chalk::IR::Node::Return',
                                'first return is a Return node');

                            # The Return node's inputs: [control, value]
                            # The value input should be a Constant node with value 'Add'
                            my $inputs = $ret_node->inputs();
                            my $value_input = $inputs->[1];
                            ok(defined $value_input,
                                'Return node has a value input (the implicit return value)');
                        }
                    }
                }
            }
        }
    }
}

# ============================================================
# 2. nodes() — the Return node appears in graph->nodes()
# ============================================================

{
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    open my $fh, '<:utf8', 'lib/Chalk/IR/Node/Constant.pm'
        or BAIL_OUT("Cannot read Constant.pm: $!");
    local $/;
    my $source = <$fh>;
    close $fh;

    my $result = $parser->parse_value($source);

    SKIP: {
        skip 'no parse result', 5 unless defined $result;

        my $ir = $result->extract();

        SKIP: {
            skip 'no IR', 4 unless defined $ir;

            my ($cls) = $ir->classes()->@*;
            skip 'no class', 3 unless defined $cls;

            my $body = $cls isa Chalk::IR::ClassInfo
                ? $cls->body()
                : $cls->inputs()->[2];

            my ($op_method) = grep {
                $_ isa Chalk::IR::MethodInfo && $_->name() eq 'operation'
            } $body->@*;
            skip 'no operation()', 2 unless defined $op_method;

            my $graph  = $op_method->graph();
            skip 'no graph', 1 unless defined $graph;

            my $nodes = $graph->nodes();
            my @return_nodes = grep { $_ isa Chalk::IR::Node::Return } $nodes->@*;
            ok(scalar @return_nodes > 0,
                'graph->nodes() contains at least one Return node');
        }
    }
}

done_testing();
