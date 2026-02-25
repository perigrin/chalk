# ABOUTME: Tests Perl IR to XS compilation for Tier D1 files (6 small files).
# ABOUTME: Terminal, IR/Node, Optimizer, Preamble, VarDecl, CompositeNode — compile+load+field readers.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierD1Test/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierD1Test::grammar();
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
# 1. Terminal.pm — field $pattern, sub match
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Terminal.pm');
    ok(defined $ir, 'Terminal: parse produces IR');

    SKIP: {
        skip 'Terminal: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD1::Terminal';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Terminal: XS builds') or do {
            diag $err;
            skip 'Terminal: build failed', 2;
        };

        # Terminal has no fields — just a class with sub match.
        # XS emits MODULE line; behavioral match() is in the PM stub.
        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Terminal: XS has MODULE line');

        my $term = eval { $module->new() };
        is($@, '', 'Terminal: new() succeeds');
    }
}

# ============================================================
# 2. IR/Node.pm — id, inputs, consumers, add_consumer
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/IR/Node.pm');
    ok(defined $ir, 'IR/Node: parse produces IR');

    SKIP: {
        skip 'IR/Node: no IR', 6 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD1::IRNode';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'IR/Node: XS builds') or do {
            diag $err;
            skip 'IR/Node: build failed', 4;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'IR/Node: XS has MODULE line');
        like($xs_code, qr/id\(self\)/, 'IR/Node: XS has id reader');

        my $node = eval { $module->new(id => 'test-1') };
        is($@, '', 'IR/Node: new() succeeds') or skip 'IR/Node: new failed', 1;
        is($node->id(), 'test-1', 'IR/Node: id reader');
    }
}

# ============================================================
# 3. Optimizer.pm — field $passes, methods add_pass, optimize
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Optimizer.pm');
    ok(defined $ir, 'Optimizer: parse produces IR');

    SKIP: {
        skip 'Optimizer: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD1::Optimizer';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Optimizer: XS builds') or do {
            diag $err;
            skip 'Optimizer: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Optimizer: XS has MODULE line');

        my $opt = eval { $module->new() };
        is($@, '', 'Optimizer: new() succeeds') or skip 'Optimizer: new failed', 1;
        is($opt->pass_count(), 0, 'Optimizer: pass_count() is 0');
    }
}

# ============================================================
# 4. Target/XS/AST/Preamble.pm — emit method
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Target/XS/AST/Preamble.pm');
    ok(defined $ir, 'Preamble: parse produces IR');

    SKIP: {
        skip 'Preamble: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD1::Preamble';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Preamble: XS builds') or do {
            diag $err;
            skip 'Preamble: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'Preamble: XS has MODULE line');
        like($xs_code, qr/emit\(/, 'Preamble: XS has emit method');

        SKIP: {
            skip 'Preamble: behavioral tests need parent class stub', 1;
            my $p = eval { $module->new() };
            ok(defined $p, 'Preamble: new() succeeds');
        }
    }
}

# ============================================================
# 5. Target/XS/AST/VarDecl.pm — type, name fields + emit
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Target/XS/AST/VarDecl.pm');
    ok(defined $ir, 'VarDecl: parse produces IR');

    SKIP: {
        skip 'VarDecl: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD1::VarDecl';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'VarDecl: XS builds') or do {
            diag $err;
            skip 'VarDecl: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'VarDecl: XS has MODULE line');
        like($xs_code, qr/emit\(/, 'VarDecl: XS has emit method');

        SKIP: {
            skip 'VarDecl: behavioral tests need parent class stub', 1;
            my $d = eval { $module->new(type => 'SV *', name => 'result') };
            ok(defined $d, 'VarDecl: new() succeeds');
        }
    }
}

# ============================================================
# 6. Target/XS/AST/CompositeNode.pm — children + emit
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Target/XS/AST/CompositeNode.pm');
    ok(defined $ir, 'CompositeNode: parse produces IR');

    SKIP: {
        skip 'CompositeNode: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierD1::CompositeNode';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'CompositeNode: XS builds') or do {
            diag $err;
            skip 'CompositeNode: build failed', 3;
        };

        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        my $xs_code = $dist->{$xs_file};
        like($xs_code, qr/MODULE\s*=/, 'CompositeNode: XS has MODULE line');
        like($xs_code, qr/emit\(/, 'CompositeNode: XS has emit method');

        SKIP: {
            skip 'CompositeNode: behavioral tests need parent class stub', 1;
            my $cn = eval { $module->new(children => []) };
            ok(defined $cn, 'CompositeNode: new() succeeds');
        }
    }
}

done_testing();
