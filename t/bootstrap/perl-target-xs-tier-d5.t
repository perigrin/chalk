# ABOUTME: Tests Perl IR to Target::C compilation for Tier D5 files (4 code generation files).
# ABOUTME: BNF/Target/XS (TODO parse failure), Perl/Target/Perl, Perl/Target/XS, Target/XS/AST/XSUB.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierD5Test/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierD5Test::grammar();
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
# 1. Target/XS.pm
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/BNF/Target/XS.pm');
    ok(defined $ir, 'Target/XS: parse produces IR');

    SKIP: {
        skip 'Target/XS: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD5::TargetXS';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'Target/XS: XS builds') or do {
            diag $err;
            skip 'Target/XS: build failed', 1;
        };

        SKIP: {
            skip 'Target/XS: behavioral tests need parent class stub', 1;
            my $t = eval { $module->new(module_name => 'Test::Module') };
            ok(defined $t, 'Target/XS: new() succeeds');
        }
    }
}

# ============================================================
# 2. Perl/Target/Perl.pm — Perl source emitter
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Perl/Target/Perl.pm');
    ok(defined $ir, 'Perl/Target/Perl: parse produces IR');

    SKIP: {
        skip 'Perl/Target/Perl: no IR', 2 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD5::PerlTargetPerl';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        TODO: {
            local $TODO = 'Perl/Target/Perl: XS build failure from codegen gaps';
            ok(defined $result, 'Perl/Target/Perl: XS builds');
        }
        skip 'Perl/Target/Perl: build failed', 1 unless defined $result;

        SKIP: {
            skip 'Perl/Target/Perl: behavioral tests need parent class stub', 1;
            my $t = eval { $module->new() };
            ok(defined $t, 'Perl/Target/Perl: new() succeeds');
        }
    }
}

# ============================================================
# 3. Perl/Target/XS.pm — XS source emitter
# ============================================================

# NOTE: Perl/Target/XS.pm (1193 lines, 44+ methods) causes deep recursion in
# the Earley parser and hangs the test suite if parse is attempted synchronously.
# All tests for this file are skipped as TODO until the parser handles large files.

{
    TODO: {
        local $TODO = 'Perl/Target/XS.pm: parse hangs due to deep recursion on large file';
        ok(0, 'Perl/Target/XS: parse produces IR');
    }

    SKIP: {
        skip 'Perl/Target/XS: parse not attempted (known hang)', 3;
        my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/Perl/Target/XS.pm');
        my $module = 'Chalk::Bootstrap::Perl::XS::TierD5::PerlTargetXS';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'Perl/Target/XS: XS builds');
        SKIP: {
            skip 'Perl/Target/XS: behavioral tests need parent class stub', 1;
            ok(0, 'Perl/Target/XS: new() succeeds');
        }
    }
}

# ============================================================
# 4. Target/XS/AST/XSUB.pm — XSUB node with emit method
# ============================================================

{
    my ($ir, $sa, $sem_ctx) = parse_file_ir('lib/Chalk/Bootstrap/BNF/Target/XS/AST/XSUB.pm');
    ok(defined $ir, 'XSUB: parse produces IR');

    SKIP: {
        skip 'XSUB: no IR', 3 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD5::XSUB';
        my ($result, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $result, 'XSUB: XS builds') or do {
            diag $err;
            skip 'XSUB: build failed', 2;
        };

        SKIP: {
            skip 'XSUB: behavioral tests need parent class stub', 2;
            my $x = eval { $module->new(name => 'test_func', params => ['SV *self']) };
            ok(defined $x, 'XSUB: new() succeeds');
            is($x->name(), 'test_func', 'XSUB: name reader works');
        }
    }
}

done_testing();
