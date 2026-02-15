# ABOUTME: Build integration test for XS code generation of the 63-rule Perl grammar.
# ABOUTME: Compiles generated XS and validates two-way recognizer equivalence (M4=M5).
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

# === Generate distribution from 63-rule Perl grammar ===

use TestPipeline qw(perl_pipeline build_perl_recognizer grammars_match);
use Chalk::Bootstrap::Target::XS;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Optimizer;
use Chalk::Bootstrap::Optimizer::DCE;

my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces IR');

# Optimize the Perl grammar IR (same as optimized_pipeline does for BNF)
my $optimizer = Chalk::Bootstrap::Optimizer->new();
$optimizer->add_pass(Chalk::Bootstrap::Optimizer::DCE->new());
my $ir = $optimizer->optimize($raw_ir);
ok(defined $ir, 'DCE optimization produces IR');
is(ref($ir), 'ARRAY', 'optimized IR is an arrayref');
is(scalar $ir->@*, 63, 'optimized IR has 63 rules');

my $target = Chalk::Bootstrap::Target::XS->new(
    module_name => 'Chalk::Grammar::Perl::Rules',
);
my $dist = $target->generate_distribution($ir);
is(ref($dist), 'HASH', 'generate_distribution returns hashref');
is(scalar keys $dist->%*, 3, 'distribution has 3 files');

# === Write to temp directory ===

my $tmpdir = tempdir(CLEANUP => 1);
ok(-d $tmpdir, 'temp directory created');

for my $path (sort keys $dist->%*) {
    my $full_path = "$tmpdir/$path";
    my $dir = dirname($full_path);
    make_path($dir) unless -d $dir;
    open(my $fh, '>:encoding(UTF-8)', $full_path) or die "Cannot write $full_path: $!";
    print $fh $dist->{$path};
    close $fh;
    ok(-f $full_path, "wrote $path");
}

# === Build cycle ===

# Run Build.PL
{
    my $output = `cd "$tmpdir" && "$^X" Build.PL 2>&1`;
    my $exit = $? >> 8;
    is($exit, 0, 'perl Build.PL exits cleanly') or diag $output;
    ok(-f "$tmpdir/Build", 'Build script created');
}

# Run ./Build
{
    my $output = `cd "$tmpdir" && "$^X" Build 2>&1`;
    my $exit = $? >> 8;
    is($exit, 0, './Build compiles XS successfully') or diag $output;
    ok(-d "$tmpdir/blib", 'blib directory created');
}

# === Load XS module ===

# Add blib paths for the compiled XS module
unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";

{
    eval { require Chalk::Grammar::Perl::Rules };
    is($@, '', 'Chalk::Grammar::Perl::Rules loads without error') or diag $@;
}

# === Verify all 63 rule methods ===

# M4: Generate Perl-target grammar for rule name extraction and equivalence
my $perl_target = Chalk::Bootstrap::Target::Perl->new();
my $perl_code = $perl_target->generate($ir);
# Use a distinct class name to avoid collision with other tests
$perl_code =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSBuildGenerated/g;
eval $perl_code;
is($@, '', 'M4: generated Perl evals without error') or diag $@;
my $m4_grammar = Chalk::Grammar::Perl::XSBuildGenerated::grammar();
ok(defined $m4_grammar, 'M4: Perl-generated grammar loaded');
is(scalar $m4_grammar->@*, 63, 'M4: 63 rules');

# Extract rule names from M4 grammar dynamically
my @rule_names = map { $_->name() } $m4_grammar->@*;

# Verify XS module has all rule methods
for my $name (@rule_names) {
    ok(Chalk::Grammar::Perl::Rules->can($name), "XS module has $name method");
}

# === Call each rule method and build grammar array ===

my @xs_rules;
for my $name (@rule_names) {
    my $rule = eval { Chalk::Grammar::Perl::Rules->$name() };
    is($@, '', "calling $name() succeeds") or diag $@;
    isa_ok($rule, 'Chalk::Grammar::Rule', "$name() returns a Rule object");
    push @xs_rules, $rule if defined $rule;
}

# === Two-way grammar equivalence (M4 = M5) ===

is(scalar @xs_rules, 63, 'M5: XS-generated grammar has 63 rules');
ok(grammars_match($m4_grammar, \@xs_rules), 'M4 == M5: Perl-generated matches XS-generated');

# === Recognizer acceptance tests ===

# Build Boolean Earley recognizers from both M4 and M5 with start => 'Program'
my @grammars = (
    ['M4 (Perl-generated)' => $m4_grammar],
    ['M5 (XS-generated)'   => \@xs_rules],
);

# Read representative .pm files (one per tier)
my @test_files = (
    'lib/Chalk/Bootstrap/IR/Node/Start.pm',      # Tier A (smallest)
    'lib/Chalk/Bootstrap/IR/Node/Constant.pm',    # Tier B
    'lib/Chalk/Bootstrap/ConciseOp.pm',           # Tier C
    'lib/Chalk/Grammar/Rule.pm',                  # Tier D
);

my %file_contents;
for my $file (@test_files) {
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    $file_contents{$file} = <$fh>;
}

for my $pair (@grammars) {
    my ($label, $grammar) = $pair->@*;
    my $recognizer = build_perl_recognizer($grammar, start => 'Program');
    ok(defined $recognizer, "$label: recognizer built");

    SKIP: {
        skip "$label: recognizer not built", scalar(@test_files) + 1
            unless defined $recognizer;

        # Accept real .pm files
        for my $file (@test_files) {
            ok($recognizer->parse($file_contents{$file}),
                "$label: accepts $file");
        }

        # Reject invalid input (not valid Perl at any level)
        ok(!$recognizer->parse('@@@ !!!'),
            "$label: rejects invalid input");
    }
}

done_testing();
