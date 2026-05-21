# ABOUTME: Integration test for MOP population during a full parse pipeline run.
# ABOUTME: Verifies that parsing a class with fields, methods, and use statements populates the MOP correctly.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# ============================================================
# Build the generated Perl grammar once for all parse tests
# ============================================================

my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

SKIP: {
    skip 'perl_pipeline returned undef', 21 unless defined $raw_ir;

    my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated  = $bnf_target->generate($raw_ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ParseIntegrationTest/g;
    eval $generated;
    is($@, '', 'generated grammar code evals cleanly')
        or BAIL_OUT("Cannot continue: $@");

    my $gen_grammar = Chalk::Grammar::Perl::ParseIntegrationTest::grammar();
    ok(defined $gen_grammar, 'grammar objects loaded');

    # ============================================================
    # Test: parse a class with field, method, and use statement
    # ============================================================
    #
    # Source contains:
    #   - use strict                    -> 1 import on main
    #   - class Point { ... }           -> 1 additional class
    #     - field $x :param :reader     -> 1 field on Point
    #     - method magnitude() { ... }  -> 1 method on Point
    # ============================================================

    my $source = q{
use strict;

class Point {
    field $x :param :reader;

    ADJUST {
        $x = 0;
    }

    method magnitude() {
        return 1;
    }
}
};

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');

    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    ok(defined $mop, 'pipeline MOP is defined before parse');

    my $result = $parser->parse_value($source);
    ok(defined $result && !$result->is_zero(), 'source with class, field, method, and use parses successfully')
        or diag('parse returned ' . (defined $result ? 'zero' : 'undef'));

    SKIP: {
        skip 'parse returned undef or zero', 17
            unless defined $result && !$result->is_zero();

        # MOP class count: main + Point
        my @classes = $mop->classes();
        is(scalar @classes, 2, 'MOP has exactly 2 classes (main and Point)')
            or diag('Got ' . scalar @classes . ' classes: ' . join(', ', map { $_->name } @classes));

        # Point class assertions
        my $point = $mop->for_class('Point');
        ok(defined $point, 'Point class is registered on MOP');

        SKIP: {
            skip 'Point class not found', 7 unless defined $point;

            my @fields = $point->fields();
            is(scalar @fields, 1, 'Point has exactly 1 field');

            SKIP: {
                skip 'no fields on Point', 2 unless scalar @fields >= 1;
                is($fields[0]->name, '$x', 'Point field is named $x');
            }

            my @methods = $point->methods();
            is(scalar @methods, 1, 'Point has exactly 1 method');

            SKIP: {
                skip 'no methods on Point', 2 unless scalar @methods >= 1;
                is($methods[0]->name, 'magnitude', 'Point method is named magnitude');
            }

            my @adjust = $point->adjust_blocks();
            is(scalar @adjust, 1, 'Point has exactly 1 ADJUST block');

            my @point_imports = $point->imports();
            is(scalar @point_imports, 0, 'Point has no imports (use belongs to main)');
        }

        # main class assertions
        my $main = $mop->for_class('main');
        ok(defined $main, 'main class is registered on MOP');

        SKIP: {
            skip 'main class not found', 5 unless defined $main;

            my @main_imports = $main->imports();
            is(scalar @main_imports, 1, 'main has exactly 1 import');

            SKIP: {
                skip 'no imports on main', 1 unless scalar @main_imports >= 1;
                is($main_imports[0]->module, 'strict', 'main import is strict');
            }

            my @main_fields  = $main->fields();
            my @main_methods = $main->methods();
            is(scalar @main_fields,  0, 'main has no fields');
            is(scalar @main_methods, 0, 'main has no methods');
        }
    }
}

done_testing();
