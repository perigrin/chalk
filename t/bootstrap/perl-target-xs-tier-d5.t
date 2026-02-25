# ABOUTME: Tests Perl IR to XS compilation for Tier D5 files (4 code generation files).
# ABOUTME: Target/XS (TODO parse failure), Perl/Target/Perl, Perl/Target/XS, Target/XS/AST/XSUB.
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
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierD5Test/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierD5Test::grammar();
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
    my $dist;
    eval { $dist = $xs_target->generate_distribution($ir) };
    if ($@) {
        return (undef, "generate_distribution died: $@");
    }
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
# 1. Target/XS.pm
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Target/XS.pm');
    ok(defined $ir, 'Target/XS: parse produces IR');

    SKIP: {
        skip 'Target/XS: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD5::TargetXS';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Target/XS: XS builds') or do {
            diag $err;
            skip 'Target/XS: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Target/XS: XS has MODULE line');
        like($xs_code, qr/module_name\(self\)/, 'Target/XS: XS has module_name reader');

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
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Perl/Target/Perl.pm');
    ok(defined $ir, 'Perl/Target/Perl: parse produces IR');

    SKIP: {
        skip 'Perl/Target/Perl: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD5::PerlTargetPerl';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Perl/Target/Perl: XS builds') or do {
            diag $err;
            skip 'Perl/Target/Perl: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Perl/Target/Perl: XS has MODULE line');

        SKIP: {
            skip 'Perl/Target/Perl: behavioral tests need parent class stub', 2;
            my $t = eval { $module->new() };
            ok(defined $t, 'Perl/Target/Perl: new() succeeds');
            is($@, '', 'Perl/Target/Perl: new() no error');
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
        skip 'Perl/Target/XS: parse not attempted (known hang)', 4;
        my $ir = parse_file_ir('lib/Chalk/Bootstrap/Perl/Target/XS.pm');
        my $module = 'Chalk::Bootstrap::Perl::XS::TierD5::PerlTargetXS';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Perl/Target/XS: XS builds');
        like($dist->{'placeholder'}, qr/MODULE\s*=/, 'Perl/Target/XS: XS has MODULE line');
        like($dist->{'placeholder'}, qr/module_name\(self\)/, 'Perl/Target/XS: XS has module_name reader');
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
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Target/XS/AST/XSUB.pm');
    ok(defined $ir, 'XSUB: parse produces IR');

    SKIP: {
        skip 'XSUB: no IR', 7 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD5::XSUB';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'XSUB: XS builds') or do {
            diag $err;
            skip 'XSUB: build failed', 5;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'XSUB: XS has MODULE line');
        like($xs_code, qr/name\(self\)/, 'XSUB: XS has name reader');
        like($xs_code, qr/return_type\(self\)/, 'XSUB: XS has return_type reader');

        SKIP: {
            skip 'XSUB: behavioral tests need parent class stub', 2;
            my $x = eval { $module->new(name => 'test_func', params => ['SV *self']) };
            ok(defined $x, 'XSUB: new() succeeds');
            is($x->name(), 'test_func', 'XSUB: name reader works');
        }
    }
}

done_testing();
