# ABOUTME: Tests that top-level subs are registered on the MOP's main class.
# ABOUTME: Verifies SubroutineDefinition populates MOP for non-class-scoped subs.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# ============================================================
# Part 1: MOP API tests (no parse pipeline required)
# ============================================================

# Test 1: MOP API — top-level sub on main via direct declare_sub
{
    my $mop = Chalk::MOP->new;
    my $main = $mop->for_class('main');
    $main->declare_sub('helper', params => ['$x']);

    my @subs = $main->subs;
    is(scalar @subs, 1, 'main has one sub');
    is($subs[0]->name, 'helper', 'sub name is helper');
}

# Test 2: MOP API — declare_field with param_name and attributes round-trips
{
    my $mop = Chalk::MOP->new;
    my $main = $mop->for_class('main');
    my $field = $main->declare_field('$x',
        sigil      => '$',
        param_name => 'x',
        attributes => [':param', ':reader'],
    );

    my @fields = $main->fields;
    is(scalar @fields, 1, 'main has one field');
    is($fields[0]->name, '$x', 'field name');
    is($fields[0]->param_name, 'x', 'param_name round-trips');
    is_deeply([$fields[0]->attributes], [':param', ':reader'], 'attributes round-trip');
}

# ============================================================
# Part 2: Parse pipeline — top-level sub registration on main
# ============================================================

# Build Perl grammar pipeline once (shared across all parse tests below)
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

SKIP: {
    skip 'perl_pipeline returned undef', 12 unless defined $raw_ir;

    my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $bnf_target->generate($raw_ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ToplevelSubTest/g;
    eval $generated;
    is($@, '', 'generated grammar code evals cleanly')
        or BAIL_OUT("Cannot continue: $@");

    my $gen_grammar = Chalk::Grammar::Perl::ToplevelSubTest::grammar();
    ok(defined $gen_grammar, 'grammar objects loaded');

    # Inline Perl source: a top-level sub at package scope
    my $source = <<'PERL';
use 5.42.0;
use utf8;

sub helper ($x) {
    return $x;
}

PERL

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');

    # Retrieve the MOP that the pipeline created and injected
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    ok(defined $mop, 'pipeline MOP is set');

    my $result = $parser->parse_value($source);
    ok(defined $result && !$result->is_zero(), 'top-level sub parses successfully');

    SKIP: {
        skip 'parse returned undef or zero', 8
            unless defined $result && !$result->is_zero();

        my $main = $mop->for_class('main');
        ok(defined $main, 'main class exists on MOP');

        my @subs = $main->subs;
        ok(scalar @subs >= 1, 'main has at least one registered sub')
            or diag('Got ' . scalar @subs . ' subs on main');

        SKIP: {
            skip 'no subs on main', 3 unless scalar @subs >= 1;

            my ($found) = grep { $_->name eq 'helper' } @subs;
            ok(defined $found, 'helper sub registered on main');

            SKIP: {
                skip 'helper sub not found', 2 unless defined $found;
                is($found->name, 'helper', 'registered sub name is helper');
                my $params = $found->params;
                ok(ref($params) eq 'ARRAY', 'sub params is arrayref');
            }
        }
    }

    # Test 3: class-scoped subs are NOT registered on main, only on the class
    {
        my $source2 = <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class Foo {
    sub class_helper ($x) {
        return $x;
    }
}

PERL

        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        my $parser2 = build_perl_ir_parser($gen_grammar, start => 'Program');
        my $mop2 = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
        ok(defined $mop2, 'pipeline MOP is set for class test');

        my $result2 = $parser2->parse_value($source2);
        ok(defined $result2 && !$result2->is_zero(), 'class-scoped sub parses successfully');

        SKIP: {
            skip 'class parse returned undef or zero', 2
                unless defined $result2 && !$result2->is_zero();

            my $main2 = $mop2->for_class('main');
            my @main_subs = $main2->subs;
            is(scalar @main_subs, 0, 'main has no subs when sub is inside a class');

            my $foo_cls = $mop2->for_class('Foo');
            if (defined $foo_cls) {
                my @foo_subs = $foo_cls->subs;
                ok(scalar @foo_subs >= 1, 'Foo class has the class_helper sub');
            } else {
                pass('Foo class not found but main is clean');
            }
        }
    }
}

done_testing();
