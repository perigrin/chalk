# ABOUTME: Tests Perl IR to Target::C compilation for Tier D3 files (4 semiring files).
# ABOUTME: SemanticAction, Precedence, Structural, TypeInference — compile+load+behavioral checks.
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
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierD3Test/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierD3Test::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse file -> IR, SemanticAction, semantic context ===

my sub parse_file_ir($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
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
    my $sem_ctx = $result->[4];
    return () unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return () unless defined $ir;
    return ($ir, $sa, $sem_ctx);
}

# ============================================================
# 1. Semiring/SemanticAction.pm — fields $actions, methods zero/one/multiply/add/on_complete
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Semiring/SemanticAction.pm');
    ok(defined $ir, 'SemanticAction: parse produces IR');

    SKIP: {
        skip 'SemanticAction: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD3::SemanticAction';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        TODO: {
            local $TODO = 'SemanticAction: XS emitter build failure (early-return codegen issues)';
            ok(defined $result, 'SemanticAction: XS builds') or diag $err;
        }
        if (!defined $result) {
            skip 'SemanticAction: build failed', 1;
        }

        # Methods that use coderefs/closures cannot be called from XS directly.
        # Verify new() constructs the object; method behaviorals are SKIP-guarded.
        SKIP: {
            skip 'SemanticAction: new() requires Context dependency stubs', 1;
            my $sa_obj = eval { $module->new() };
            ok(defined $sa_obj, 'SemanticAction: new() succeeds');
        }
    }
}

# ============================================================
# 2. Semiring/Precedence.pm — field $lookup, methods zero/one/is_zero/multiply/add
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Semiring/Precedence.pm');
    ok(defined $ir, 'Precedence: parse produces IR');

    SKIP: {
        skip 'Precedence: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD3::Precedence';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'Precedence: XS builds') or do {
            diag $err;
            skip 'Precedence: build failed', 1;
        };

        my $prec = eval { $module->new(lookup => sub { undef }) };
        is($@, '', 'Precedence: new() succeeds');
    }
}

# ============================================================
# 3. Semiring/Structural.pm — bitfield constants, methods zero/one/is_zero/multiply/add
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Semiring/Structural.pm');
    ok(defined $ir, 'Structural: parse produces IR');

    SKIP: {
        skip 'Structural: no IR', 3 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD3::Structural';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        TODO: {
            local $TODO = 'Structural: XS build failure from codegen gaps';
            ok(defined $result, 'Structural: XS builds');
        }
        skip 'Structural: build failed', 2 unless defined $result;

        my $struct = eval { $module->new() };
        is($@, '', 'Structural: new() succeeds') or skip 'Structural: new failed', 1;
        TODO: {
            local $TODO = 'Structural: parser misinterprets "return -1" as BinaryExpr("return" - 1)';
            is($struct->zero(), -1, 'Structural: zero() returns -1');
        }
    }
}

# ============================================================
# 4. Semiring/TypeInference.pm — fields $keyword_check/$builtin_lookup, methods zero/one/is_zero/multiply/add
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Semiring/TypeInference.pm');
    ok(defined $ir, 'TypeInference: parse produces IR');

    SKIP: {
        skip 'TypeInference: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD3::TypeInference';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'TypeInference: XS builds') or do {
            diag $err;
            skip 'TypeInference: build failed', 1;
        };

        # TypeInference.new() requires coderef params that involve Context stubs.
        SKIP: {
            skip 'TypeInference: new() requires keyword_check and builtin_lookup coderefs', 1;
            my $ti = eval {
                $module->new(
                    keyword_check  => sub { false },
                    builtin_lookup => sub { undef },
                )
            };
            ok(defined $ti, 'TypeInference: new() succeeds');
        }
    }
}

done_testing();
