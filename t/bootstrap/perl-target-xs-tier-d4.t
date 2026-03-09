# ABOUTME: Tests Perl IR to XS compilation for Tier D4 files (3 large action files).
# ABOUTME: BNF/Actions (TODO parse failure), ConciseTree/Actions, Perl/Actions — compile+load.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierD4Test/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierD4Test::grammar();
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
# 1. Grammar/BNF/Actions.pm
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Grammar/BNF/Actions.pm');
    ok(defined $ir, 'BNF/Actions: parse produces IR');

    SKIP: {
        skip 'BNF/Actions: no IR', 3 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD4::BNFActions';
        my ($dist, $err) = build_and_load($ir, $module);
        TODO: {
            local $TODO = 'BNF/Actions: XS emitter build failure (xsreturn label issues in early-return codegen)';
            ok(defined $dist, 'BNF/Actions: XS builds') or diag $err;
        }
        if (!defined $dist) {
            skip 'BNF/Actions: build failed', 2;
        }

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'BNF/Actions: XS has MODULE line');

        SKIP: {
            skip 'BNF/Actions: behavioral tests require parent class stubs', 1;
            my $obj = eval { $module->new() };
            ok(defined $obj, 'BNF/Actions: new() succeeds');
        }
    }
}

# ============================================================
# 2. ConciseTree/Actions.pm — large action file (60+ methods)
# ============================================================

{
    my $ir;
    TODO: {
        local $TODO = 'ConciseTree/Actions: parse failure on large file with complex patterns';
        $ir = parse_file_ir('lib/Chalk/Bootstrap/ConciseTree/Actions.pm');
        ok(defined $ir, 'ConciseTree/Actions: parse produces IR');
    }

    SKIP: {
        skip 'ConciseTree/Actions: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD4::ConciseTreeActions';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'ConciseTree/Actions: XS builds') or do {
            diag $err;
            skip 'ConciseTree/Actions: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'ConciseTree/Actions: XS has MODULE line');

        # Large file — verify method signatures are present in XS.
        # Complex methods use (self, param, ...) so match any self-taking signature.
        my @xs_methods = ($xs_code =~ /^\w+\(self[,)]/mg);
        ok(scalar @xs_methods >= 1,
            'ConciseTree/Actions: XS has method signatures (got ' . scalar @xs_methods . ')');

        SKIP: {
            skip 'ConciseTree/Actions: behavioral tests require B::Concise stubs', 1;
            my $obj = eval { $module->new() };
            ok(defined $obj, 'ConciseTree/Actions: new() succeeds');
        }
    }
}

# ============================================================
# 3. Perl/Actions.pm — large action file for Perl lowering (60+ methods)
# ============================================================

{
    my $ir;
    TODO: {
        local $TODO = 'Perl/Actions.pm: parse failure on large file with complex patterns';
        $ir = parse_file_ir('lib/Chalk/Bootstrap/Perl/Actions.pm');
        ok(defined $ir, 'Perl/Actions: parse produces IR');
    }

    SKIP: {
        skip 'Perl/Actions: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD4::PerlActions';
        my ($dist, $err) = build_and_load($ir, $module);
        TODO: {
            local $TODO = 'Perl/Actions: XS emitter emits undeclared literal_sv variable (variable naming mismatch in StringLiteral handler)';
            ok(defined $dist, 'Perl/Actions: XS builds') or do {
                diag $err;
            };
        }

        SKIP: {
            skip 'Perl/Actions: build failed', 3 unless defined $dist;

            my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
            my $xs_code = $dist->{$xs_file};
            like($xs_code, qr/MODULE\s*=/, 'Perl/Actions: XS has MODULE line');

            # Large file — verify method signatures are present in XS.
            # Complex methods use (self, param, ...) so match any self-taking signature.
            my @xs_methods = ($xs_code =~ /^\w+\(self[,)]/mg);
            ok(scalar @xs_methods >= 1,
                'Perl/Actions: XS has method signatures (got ' . scalar @xs_methods . ')');

            SKIP: {
                skip 'Perl/Actions: behavioral tests require complex dependency stubs', 1;
                my $obj = eval { $module->new() };
                ok(defined $obj, 'Perl/Actions: new() succeeds');
            }
        }
    }
}

done_testing();
