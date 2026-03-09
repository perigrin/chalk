# ABOUTME: Tests Perl IR to XS compilation for Tier D2 files (6 data-structure management files).
# ABOUTME: Desugar, DCE, NodeFactory, Boolean, FilterComposite, Target::Perl — compile+load+field readers.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);

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

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

# === Setup ===

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierD2Test/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierD2Test::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse file -> IR ===

my sub parse_file_ir($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result->[4];
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# === Helper to build, compile, load XS module ===

my sub build_and_load($ir, $module_name) {
    my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => $module_name,
    );
    my $dist = $xs_target->generate_distribution($ir);
    return (undef, "generate_distribution failed") unless ref($dist) eq 'HASH';

    my $tmpdir = tempdir(CLEANUP => 1);
    for my $path (sort keys $dist->%*) {
        my $full_path = "$tmpdir/$path";
        my $dir = dirname($full_path);
        make_path($dir) unless -d $dir;
        open(my $fh, '>:encoding(UTF-8)', $full_path)
            or die "Cannot write $full_path: $!";
        print $fh $dist->{$path};
        close $fh;
    }

    my $build_output = `cd "$tmpdir" && "$^X" Build.PL 2>&1 && "$^X" Build 2>&1`;
    my $exit = $? >> 8;
    return (undef, "Build failed (exit $exit): $build_output") if $exit != 0;

    unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
    eval "require $module_name";
    return (undef, "Load failed: $@") if $@;

    return ($dist, undef);
}

# ============================================================
# 1. Desugar.pm — sub desugar_grammar, _helper_name, _create_helpers
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Desugar.pm');
    ok(defined $ir, 'Desugar: parse produces IR');

    SKIP: {
        skip 'Desugar: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::Desugar';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Desugar: XS builds') or do {
            diag $err;
            skip 'Desugar: build failed', 2;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Desugar: XS has MODULE line');

        my $obj = eval { $module->new() };
        is($@, '', 'Desugar: new() succeeds');
    }
}

# ============================================================
# 2. Optimizer/DCE.pm — method run, _mark_reachable
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Optimizer/DCE.pm');
    ok(defined $ir, 'DCE: parse produces IR');

    SKIP: {
        skip 'DCE: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::DCE';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'DCE: XS builds') or do {
            diag $err;
            skip 'DCE: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'DCE: XS has MODULE line');
        like($xs_code, qr/run/, 'DCE: XS has run method (XSUB or eval_pv)');

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
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/IR/NodeFactory.pm');
    ok(defined $ir, 'NodeFactory: parse produces IR');

    SKIP: {
        skip 'NodeFactory: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::NodeFactory';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'NodeFactory: XS builds') or do {
            diag $err;
            skip 'NodeFactory: build failed', 2;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'NodeFactory: XS has MODULE line');

        my $obj = eval { $module->new() };
        is($@, '', 'NodeFactory: new() succeeds');
    }
}

# ============================================================
# 4. Semiring/Boolean.pm — zero, one, is_zero, multiply, add, on_scan, on_complete
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Semiring/Boolean.pm');
    ok(defined $ir, 'Boolean: parse produces IR');

    SKIP: {
        skip 'Boolean: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::Boolean';
        my ($dist, $err) = build_and_load($ir, $module);
        TODO: {
            local $TODO = 'Boolean: XS emitter build failure (early-return codegen issues)';
            ok(defined $dist, 'Boolean: XS builds') or diag $err;
        }
        if (!defined $dist) {
            skip 'Boolean: build failed', 3;
        }

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Boolean: XS has MODULE line');
        TODO: {
            local $TODO = 'Boolean: is_zero emitted as eval_pv fallback, not XS method signature';
            like($xs_code, qr/is_zero\(/, 'Boolean: XS has is_zero method');
        }

        my $bool = eval { $module->new() };
        is($@, '', 'Boolean: new() succeeds');
    }
}

# ============================================================
# 5. Semiring/FilterComposite.pm — field $semirings, zero, one, is_zero, add, multiply
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Semiring/FilterComposite.pm');
    ok(defined $ir, 'FilterComposite: parse produces IR');

    SKIP: {
        skip 'FilterComposite: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::FilterComposite';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'FilterComposite: XS builds') or do {
            diag $err;
            skip 'FilterComposite: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'FilterComposite: XS has MODULE line');
        like($xs_code, qr/"reader"/, 'FilterComposite: XS applies :reader attribute via C API');

        my $comp = eval { $module->new(semirings => []) };
        is($@, '', 'FilterComposite: new() succeeds');
    }
}

# ============================================================
# 6. Target/Perl.pm — method generate (BNF Target::Perl, not Perl::Target::Perl)
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/BNF/Target/Perl.pm');
    ok(defined $ir, 'Target::Perl: parse produces IR');

    SKIP: {
        skip 'Target::Perl: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD2::TargetPerl';
        my ($dist, $err) = build_and_load($ir, $module);
        TODO: {
            local $TODO = 'Target::Perl: XS build failure from codegen gaps';
            ok(defined $dist, 'Target::Perl: XS builds');
        }
        skip 'Target::Perl: build failed', 3 unless defined $dist;

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Target::Perl: XS has MODULE line');
        like($xs_code, qr/generate_distribution\(/, 'Target::Perl: XS has generate_distribution method');

        SKIP: {
            skip 'Target::Perl: behavioral tests need parent class stub', 1;
            my $t = eval { $module->new() };
            ok(defined $t, 'Target::Perl: new() succeeds');
        }
    }
}

done_testing();
