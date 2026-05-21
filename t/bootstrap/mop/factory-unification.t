# ABOUTME: Tests that Phase 7d Step 1 unifies the per-parse factory.
# ABOUTME: After parser setup, $ctx->factory() at action-time is the
# ABOUTME: SAME instance Actions holds as $typed. _one_ctx no longer
# ABOUTME: allocates its own factory — it reads the one injected via
# ABOUTME: SemanticAction::set_factory.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Actions;
use Chalk::IR::NodeFactory;

# SemanticAction has a set_factory class-method, analogous to set_mop.
subtest 'SA::set_factory class method exists' => sub {
    can_ok('Chalk::Bootstrap::Semiring::SemanticAction', 'set_factory');
};

# After set_factory($f) and reset_cache, _one_ctx uses the injected
# factory rather than allocating its own.
subtest 'set_factory injects factory into _one_ctx' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_factory($f);
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new;
    my $one = $sa->one;
    is(refaddr($one->factory), refaddr($f),
        'one() Context carries the injected factory');
};

# Two consecutive parses can each inject their own factory; the
# previous one is replaced by set_factory.
subtest 'set_factory replaces previously injected factory' => sub {
    my $f1 = Chalk::IR::NodeFactory->new;
    my $f2 = Chalk::IR::NodeFactory->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_factory($f1);
    my $sa1 = Chalk::Bootstrap::Semiring::SemanticAction->new;
    my $one1 = $sa1->one;
    is(refaddr($one1->factory), refaddr($f1), 'first parse uses f1');

    Chalk::Bootstrap::Semiring::SemanticAction::set_factory($f2);
    my $sa2 = Chalk::Bootstrap::Semiring::SemanticAction->new;
    my $one2 = $sa2->one;
    is(refaddr($one2->factory), refaddr($f2), 'second parse uses f2');
    isnt(refaddr($one1->factory), refaddr($one2->factory),
        'two parses see distinct factories');
};

# set_factory(undef) reverts to allocating a fresh factory, preserving
# the existing behavior for callers that don't inject explicitly.
subtest 'set_factory(undef) restores allocate-fresh behavior' => sub {
    Chalk::Bootstrap::Semiring::SemanticAction::set_factory(undef);
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new;
    my $one = $sa->one;
    isa_ok($one->factory, 'Chalk::IR::NodeFactory',
        'one() Context still gets a typed factory by default');
};

# Real-parse integration: Actions's ADJUST injects its $typed factory
# into SA, so the parse Context carries the SAME factory instance.
subtest 'real parse: $ctx->factory == Actions $typed' => sub {
    require TestPipeline;
    TestPipeline->import(qw(perl_pipeline build_perl_ir_parser));
    require Chalk::Bootstrap::IR::NodeFactory;
    require Chalk::Bootstrap::BNF::Target::Perl;

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing;
    Chalk::Bootstrap::Semiring::SemanticAction::set_factory(undef);

    my $raw_ir = TestPipeline::perl_pipeline();
    my $target = Chalk::Bootstrap::BNF::Target::Perl->new;
    my $generated = $target->generate($raw_ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::FactoryUnifyTest/g;
    eval $generated; die $@ if $@;
    my $g = Chalk::Grammar::Perl::FactoryUnifyTest::grammar();

    # Build parser — this constructs Actions and runs its ADJUST.
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing;
    my $parser = TestPipeline::build_perl_ir_parser($g, start => 'Program');

    # After build, set_factory should have been called with Actions's $typed.
    my $injected = Chalk::Bootstrap::Semiring::SemanticAction::current_factory();
    ok(defined $injected, 'Actions injected a factory into SA at build time');
    isa_ok($injected, 'Chalk::IR::NodeFactory',
        'injected factory is typed NodeFactory');

    # Parse and verify the result Context carries the injected factory.
    my $result = $parser->parse_value(q{class C { method foo() { 42 } }});
    ok(defined $result, 'parse succeeded');
    is(refaddr($result->factory), refaddr($injected),
        'parse-result $ctx->factory IS the injected factory');
};

done_testing;
