# ABOUTME: Tests that 'return' and 'die' are treated as keywords, not QualifiedIdentifier.
# ABOUTME: Verifies that parsing 'return EXPR' produces exactly ONE Return node, not two.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::MethodInfo;
use Chalk::IR::Graph;

# Build Perl grammar pipeline once
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::KeywordReturnDieTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::KeywordReturnDieTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

my sub parse_snippet($source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;
    return undef if $result->is_zero();
    return $result->extract();
}

my sub collect_return_nodes($graph) {
    return () unless defined $graph;
    my $nodes = $graph->nodes();
    return grep { $_ isa Chalk::IR::Node::Return } $nodes->@*;
}

my sub collect_unwind_nodes($graph) {
    return () unless defined $graph;
    my $nodes = $graph->nodes();
    return grep { $_ isa Chalk::IR::Node::Unwind } $nodes->@*;
}

# ============================================================
# 1. 'return 42;' — should produce exactly ONE Return node
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
class Foo {
    method bar() {
        return 42;
    }
}
PERL

    my $ir = parse_snippet($source);
    ok(defined $ir, 'return 42: parse produces IR');

    SKIP: {
        skip 'return 42: no IR', 4 unless defined $ir;

        my ($cls) = $ir->classes()->@*;
        ok(defined $cls, 'return 42: found class');

        SKIP: {
            skip 'return 42: no class', 3 unless defined $cls;

            my ($method) = grep { $_->name() eq 'bar' } $cls->methods()->@*;
            ok(defined $method, 'return 42: found method bar');

            SKIP: {
                skip 'return 42: no method', 2 unless defined $method;

                my $graph = $method->graph();
                ok(defined $graph, 'return 42: method has a graph');

                SKIP: {
                    skip 'return 42: no graph', 1 unless defined $graph;

                    my @returns = collect_return_nodes($graph);
                    is(scalar @returns, 1,
                        'return 42: exactly ONE Return node in graph (not two)')
                        or diag("Found " . scalar @returns . " Return node(s)");
                }
            }
        }
    }
}

# ============================================================
# 2. 'die "error";' — should produce exactly ONE Unwind node
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
class Foo {
    method bar() {
        die "error";
    }
}
PERL

    my $ir = parse_snippet($source);
    ok(defined $ir, 'die "error": parse produces IR');

    SKIP: {
        skip 'die "error": no IR', 4 unless defined $ir;

        my ($cls) = $ir->classes()->@*;
        ok(defined $cls, 'die "error": found class');

        SKIP: {
            skip 'die "error": no class', 3 unless defined $cls;

            my ($method) = grep { $_->name() eq 'bar' } $cls->methods()->@*;
            ok(defined $method, 'die "error": found method bar');

            SKIP: {
                skip 'die "error": no method', 2 unless defined $method;

                my $graph = $method->graph();
                ok(defined $graph, 'die "error": method has a graph');

                SKIP: {
                    skip 'die "error": no graph', 1 unless defined $graph;

                    my @unwinds = collect_unwind_nodes($graph);
                    is(scalar @unwinds, 1,
                        'die "error": exactly ONE Unwind node in graph (not two)')
                        or diag("Found " . scalar @unwinds . " Unwind node(s)");
                }
            }
        }
    }
}

# ============================================================
# 3. 'return;' (bare) — should produce exactly ONE Return node
# ============================================================

{
    my $source = <<'PERL';
use 5.42.0;
class Foo {
    method bar() {
        return;
    }
}
PERL

    my $ir = parse_snippet($source);
    ok(defined $ir, 'bare return: parse produces IR');

    SKIP: {
        skip 'bare return: no IR', 4 unless defined $ir;

        my ($cls) = $ir->classes()->@*;
        ok(defined $cls, 'bare return: found class');

        SKIP: {
            skip 'bare return: no class', 3 unless defined $cls;

            my ($method) = grep { $_->name() eq 'bar' } $cls->methods()->@*;
            ok(defined $method, 'bare return: found method bar');

            SKIP: {
                skip 'bare return: no method', 2 unless defined $method;

                my $graph = $method->graph();
                ok(defined $graph, 'bare return: method has a graph');

                SKIP: {
                    skip 'bare return: no graph', 1 unless defined $graph;

                    my @returns = collect_return_nodes($graph);
                    is(scalar @returns, 1,
                        'bare return: exactly ONE Return node in graph (not two)')
                        or diag("Found " . scalar @returns . " Return node(s)");
                }
            }
        }
    }
}

done_testing();
