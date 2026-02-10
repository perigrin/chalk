# ABOUTME: Tests Perl IR to XS compilation for Tier B files.
# ABOUTME: Compiles generated XS, loads module, and validates behavioral equivalence.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierBTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierBTest::grammar();
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

# === Test cases ===

# ============================================================
# 1. Constant.pm — 2 field readers + method
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/IR/Node/Constant.pm');
    ok(defined $ir, 'Constant: parse produces IR');

    SKIP: {
        skip 'Constant: no IR', 8 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Constant';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Constant: XS builds') or do {
            diag $err;
            skip 'Constant: build failed', 6;
        };

        my $obj = eval { $module->new(const_type => 'string', value => 'hello') };
        is($@, '', 'Constant: new() succeeds') or do {
            diag $@;
            skip 'Constant: new failed', 5;
        };

        is($obj->const_type(), 'string', 'Constant: const_type reader');
        is($obj->value(), 'hello', 'Constant: value reader');
        is($obj->operation(), 'Constant', 'Constant: operation() returns Constant');

        # Different values
        my $obj2 = $module->new(const_type => 'integer', value => '42');
        is($obj2->const_type(), 'integer', 'Constant: const_type reader (integer)');
        is($obj2->value(), '42', 'Constant: value reader (42)');
    }
}

# ============================================================
# 2. XS::AST::Node.pm — method with die (same as Tier A pattern)
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Target/XS/AST/Node.pm');
    ok(defined $ir, 'XS::AST::Node: parse produces IR');

    SKIP: {
        skip 'XS::AST::Node: no IR', 3 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Node';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Node: XS builds') or do {
            diag $err;
            skip 'Node: build failed', 1;
        };

        my $obj = eval { $module->new() };
        is($@, '', 'Node: new() succeeds');

        eval { $obj->emit() };
        like($@, qr/Subclass must implement emit/,
            'Node: emit() dies with expected message');
    }
}

# ============================================================
# 3. XS::AST::Statement.pm — 1 field reader + interpolated emit
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Target/XS/AST/Statement.pm');
    ok(defined $ir, 'Statement: parse produces IR');

    SKIP: {
        skip 'Statement: no IR', 5 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Statement';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Statement: XS builds') or do {
            diag $err;
            # Dump XS for debugging
            if (defined $dist) {
                for my $path (sort keys $dist->%*) {
                    diag "=== $path ===\n" . $dist->{$path} if $path =~ /\.xs$/;
                }
            }
            skip 'Statement: build failed', 3;
        };

        my $obj = eval { $module->new(code => 'RETVAL = sv;') };
        is($@, '', 'Statement: new() succeeds');

        is($obj->code(), 'RETVAL = sv;', 'Statement: code reader');
        is($obj->emit(), "    RETVAL = sv;\n", 'Statement: emit() interpolates correctly');
    }
}

# ============================================================
# 4. XS::AST::Module.pm — 2 field readers + 2-var interpolated emit
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/Target/XS/AST/Module.pm');
    ok(defined $ir, 'Module: parse produces IR');

    SKIP: {
        skip 'Module: no IR', 6 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Module';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Module: XS builds') or do {
            diag $err;
            skip 'Module: build failed', 4;
        };

        my $obj = eval { $module->new(module => 'Foo', package => 'Foo') };
        is($@, '', 'Module: new() succeeds');

        is($obj->module(), 'Foo', 'Module: module reader');
        is($obj->package(), 'Foo', 'Module: package reader');
        is($obj->emit(), "MODULE = Foo  PACKAGE = Foo\n\n",
            'Module: emit() interpolates 2 variables correctly');
    }
}

# ============================================================
# 5. Constructor.pm — 1 field reader + method
# ============================================================

{
    my $ir = parse_file_ir('lib/Chalk/Bootstrap/IR/Node/Constructor.pm');
    ok(defined $ir, 'Constructor: parse produces IR');

    SKIP: {
        skip 'Constructor: no IR', 4 unless defined $ir;

        my $module = 'Chalk::Bootstrap::Perl::XS::TierB::Constructor';
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, 'Constructor: XS builds') or do {
            diag $err;
            skip 'Constructor: build failed', 2;
        };

        my $obj = eval { $module->new(class => 'Rule') };
        is($@, '', 'Constructor: new() succeeds');

        is($obj->class(), 'Rule', 'Constructor: class reader');
        is($obj->operation(), 'Constructor', 'Constructor: operation() returns Constructor');
    }
}

done_testing();
