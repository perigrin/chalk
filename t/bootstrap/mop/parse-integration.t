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

        # ============================================================
        # Test: class-scope `my $VAR = expr;` populates class_scope_vars
        # ============================================================
        # Parse a second source against the same singleton MOP (matches
        # the convention established by parse-toplevel-sub.t line 130:
        # current_mop() is read by semantic actions; classes accumulate
        # across parses on the same singleton). No reset needed.
        {
            my $csv_source = q{
class Sentinel {
    my $ZERO = -1;
    field $x :param;

    method get_zero() {
        return $ZERO;
    }
}
};

            my $csv_parser = build_perl_ir_parser($gen_grammar, start => 'Program');
            # build_perl_ir_parser installs a fresh MOP via set_mop, so
            # capture the new singleton after parser construction
            # (matches the convention in parse-toplevel-sub.t line 130).
            my $csv_mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
            my $csv_result = $csv_parser->parse_value($csv_source);

            ok(defined $csv_result && !$csv_result->is_zero(),
                'class with class-scope `my` parses successfully');

            SKIP: {
                skip 'csv source did not parse', 3
                    unless defined $csv_result && !$csv_result->is_zero();

                my $sentinel = $csv_mop->for_class('Sentinel');
                ok(defined $sentinel, 'Sentinel class is on MOP');

                SKIP: {
                    skip 'Sentinel not on MOP', 2 unless defined $sentinel;
                    my @csv = $sentinel->class_scope_vars;
                    is(scalar @csv, 1, 'Sentinel has 1 class_scope_var');

                    SKIP: {
                        skip 'no class_scope_vars on Sentinel', 1
                            unless scalar @csv >= 1;
                        is($csv[0]->name->value, '$ZERO',
                            'class_scope_var name is $ZERO');
                    }
                }
            }
        }

        # ============================================================
        # Test: class-scope `use constant { K => V };` populates
        # use_constants (and is NOT routed to imports)
        # ============================================================
        {
            my $uc_source = q{
class Counters {
    use constant { MIN => 0, MAX => 255 };

    method min() { return MIN; }
}
};

            my $uc_parser = build_perl_ir_parser($gen_grammar, start => 'Program');
            # Capture fresh MOP (set_mop installs a new one per parser).
            my $uc_mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
            my $uc_result = $uc_parser->parse_value($uc_source);

            ok(defined $uc_result && !$uc_result->is_zero(),
                'class with `use constant` parses successfully');

            SKIP: {
                skip 'uc source did not parse', 4
                    unless defined $uc_result && !$uc_result->is_zero();

                my $counters = $uc_mop->for_class('Counters');
                ok(defined $counters, 'Counters class is on MOP');

                SKIP: {
                    skip 'Counters not on MOP', 3 unless defined $counters;

                    my @uc = $counters->use_constants;
                    is(scalar @uc, 2, 'Counters has 2 use_constants');

                    my %by_name = map { $_->{name} => $_ } @uc;
                    ok(exists $by_name{MIN}, 'use_constants has MIN');
                    ok(exists $by_name{MAX}, 'use_constants has MAX');

                    # Critically: use_constants does NOT also leak into
                    # imports. The pre-split code routed every UseInfo
                    # through declare_import, so this would have failed.
                    my @imps = $counters->imports;
                    my @constant_imps = grep { $_->module eq 'constant' } @imps;
                    is(scalar @constant_imps, 0,
                        '`use constant` does not appear in imports');
                }
            }
        }
    }
}

# Chained-decl regression: Boolean.pm has consecutive `my $ZERO_CTX; my $ONE_CTX;`
# at class scope. The parser packs these as one VarDecl whose init is another
# VarDecl. Both names must end up in class_scope_vars (presence, not order).
{
    use TestPipeline qw(parse_perl_source);
    use Scalar::Util qw(refaddr);

    my $bool_src;
    {
        open my $fh, '<:utf8', 'lib/Chalk/Bootstrap/Semiring/Boolean.pm'
            or die "Cannot read Boolean.pm: $!";
        local $/;
        $bool_src = <$fh>;
        close $fh;
    }

    # parse_perl_source is the Task-1.5b helper. It uses whatever MOP was
    # installed via SemanticAction::set_mop. Install a fresh one for this block.
    my $mop_for_parse = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop_for_parse);

    my ($ir, $sa, $ctx) = parse_perl_source($bool_src);
    ok(defined $ctx, 'Boolean.pm parses');
    my $mop = $ctx->mop;
    ok(defined $mop, 'Boolean.pm parse produces a MOP');
    is(refaddr($mop), refaddr($mop_for_parse),
       'parse ctx->mop is the installed MOP');

    my $mop_cls = $mop->for_class('Chalk::Bootstrap::Semiring::Boolean');
    ok(defined $mop_cls, 'Boolean class is registered on MOP');

    my @class_scope_var_names = map {
        my $n = $_->name->value;
        $n =~ s/^[\$\@\%]//r;
    } $mop_cls->class_scope_vars;

    my %present = map { $_ => 1 } @class_scope_var_names;
    ok($present{ZERO_CTX}, 'class_scope_vars contains ZERO_CTX (outer chained decl)');
    ok($present{ONE_CTX},  'class_scope_vars contains ONE_CTX (inner chained decl)');
}

done_testing();
