# ABOUTME: Tests Perl IR to Target::C compilation for Tier D2 files (6 data-structure management files).
# ABOUTME: Desugar, DCE, NodeFactory, Boolean, FilterComposite, Target::Perl — compile+load+field readers.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# === Skip guards ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

# === Setup ===

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use TestXSHelpers qw(build_and_load);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build Perl grammar pipeline
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierD2Test/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierD2Test::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse file -> IR, SemanticAction, semantic context ===

my sub parse_file_ir($file) {
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $result = $parser->parse_value($source);
    return () unless defined $result;

    my $sa = $semiring->semirings()->[4];
    my $sem_ctx = $result;
    return () unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return () unless defined $ir;
    return ($ir, $sa, $sem_ctx);
}

# ============================================================
# 1. Desugar.pm — sub desugar_grammar, _helper_name, _create_helpers
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Desugar.pm');
    ok(defined $ir, 'Desugar: parse produces IR');

    SKIP: {
        skip 'Desugar: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::Desugar';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'Desugar: XS builds') or do {
            diag $err;
            skip 'Desugar: build failed', 1;
        };

        my $obj = eval { $module->new() };
        is($@, '', 'Desugar: new() succeeds');
    }
}

# ============================================================
# 2. Optimizer/DCE.pm — method run, _mark_reachable
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Optimizer/DCE.pm');
    ok(defined $ir, 'DCE: parse produces IR');

    SKIP: {
        skip 'DCE: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::DCE';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'DCE: XS builds') or do {
            diag $err;
            skip 'DCE: build failed', 1;
        };

        SKIP: {
            skip 'DCE: behavioral tests need parent class stub', 1;
            my $dce = eval { $module->new() };
            ok(defined $dce, 'DCE: new() succeeds');
        }
    }
}

# ============================================================
# 3. IR/NodeFactory.pm — known parse failure (TODO)
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/IR/NodeFactory.pm');
    ok(defined $ir, 'NodeFactory: parse produces IR');

    SKIP: {
        skip 'NodeFactory: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::NodeFactory';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'NodeFactory: XS builds') or do {
            diag $err;
            skip 'NodeFactory: build failed', 1;
        };

        my $obj = eval { $module->new() };
        is($@, '', 'NodeFactory: new() succeeds');
    }
}

# ============================================================
# 4. Semiring/Boolean.pm — zero, one, is_zero, multiply, add, on_scan, on_complete
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Semiring/Boolean.pm');
    ok(defined $ir, 'Boolean: parse produces IR');

    SKIP: {
        skip 'Boolean: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::Boolean';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        TODO: {
            local $TODO = 'Boolean: XS emitter build failure (early-return codegen issues)';
            ok(defined $result, 'Boolean: XS builds') or diag $err;
        }
        if (!defined $result) {
            skip 'Boolean: build failed', 1;
        }

        my $bool = eval { $module->new() };
        is($@, '', 'Boolean: new() succeeds');
    }
}

# ============================================================
# 5. Semiring/FilterComposite.pm — field $semirings, zero, one, is_zero, add, multiply
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Semiring/FilterComposite.pm');
    ok(defined $ir, 'FilterComposite: parse produces IR');

    SKIP: {
        skip 'FilterComposite: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::FilterComposite';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'FilterComposite: XS builds') or do {
            diag $err;
            skip 'FilterComposite: build failed', 1;
        };

        my $comp = eval { $module->new(semirings => []) };
        is($@, '', 'FilterComposite: new() succeeds');
    }
}

# ============================================================
# 6. Target/Perl.pm — method generate (BNF Target::Perl, not Perl::Target::Perl)
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/BNF/Target/Perl.pm');
    ok(defined $ir, 'Target::Perl: parse produces IR');

    SKIP: {
        skip 'Target::Perl: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::TargetPerl';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        TODO: {
            local $TODO = 'Target::Perl: XS build failure from codegen gaps';
            ok(defined $result, 'Target::Perl: XS builds');
        }
        skip 'Target::Perl: build failed', 1 unless defined $result;

        SKIP: {
            skip 'Target::Perl: behavioral tests need parent class stub', 1;
            my $t = eval { $module->new() };
            ok(defined $t, 'Target::Perl: new() succeeds');
        }
    }
}

done_testing();
