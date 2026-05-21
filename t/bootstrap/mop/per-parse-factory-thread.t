# ABOUTME: Tests that a per-parse Chalk::IR::NodeFactory is seeded
# ABOUTME: into _one_ctx and propagates through every Context derived
# ABOUTME: from it. Action methods can read $ctx->factory() and get
# ABOUTME: this parse's factory instead of the Bootstrap singleton.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);
use lib 'lib';

use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::IR::NodeFactory;

# Reset state between assertions.
my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new;
$sa->reset_cache;

# The one() Context must have a factory field set.
my $one = $sa->one;
isa_ok($one->factory, 'Chalk::IR::NodeFactory',
    'one() Context carries a typed NodeFactory');

# Two consecutive calls without resetting return the same singleton —
# same factory, same Context.
my $one2 = $sa->one;
is(refaddr($one->factory), refaddr($one2->factory),
    'same one() Context yields the same factory across calls');

# After reset_cache, the next one() Context has a FRESH factory.
$sa->reset_cache;
my $one_new = $sa->one;
isnt(refaddr($one->factory), refaddr($one_new->factory),
    'reset_cache produces a fresh factory in the next one()');

# Extending the one() Context propagates the factory.
my $extended = $one_new->extend(sub ($c) { 'derived' });
is(refaddr($extended->factory), refaddr($one_new->factory),
    'extend propagates the parse-level factory to children');

# Integration: a real parse threads the factory all the way to the
# top-level parse result and into deeper Contexts under FilterComposite.
subtest 'factory threads through full parse pipeline' => sub {
    require lib;
    lib->import('t/bootstrap/lib');
    require TestPipeline;
    TestPipeline->import(qw(perl_pipeline build_perl_ir_parser));
    require Chalk::Bootstrap::IR::NodeFactory;
    require Chalk::Bootstrap::BNF::Target::Perl;

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing;
    my $raw_ir = TestPipeline::perl_pipeline();
    my $target = Chalk::Bootstrap::BNF::Target::Perl->new;
    my $generated = $target->generate($raw_ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::FactoryThreadTest/g;
    eval $generated; die $@ if $@;
    my $g = Chalk::Grammar::Perl::FactoryThreadTest::grammar();

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing;
    my $parser = TestPipeline::build_perl_ir_parser($g, start => 'Program');
    my $result = $parser->parse_value(q{class C { method foo() { 42 } }});

    ok(defined $result, 'parse succeeded');
    ok(defined $result->factory,
        'top-level parse result has factory threaded from one()');
    isa_ok($result->factory, 'Chalk::IR::NodeFactory',
        'factory is the typed per-parse factory, not Bootstrap singleton');
};

done_testing;
