# ABOUTME: Build integration test for the XS code generation target.
# ABOUTME: Compiles generated XS and validates three-way recognizer equivalence.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Chalk::Grammar::BNF;

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

# === Generate distribution ===

use TestPipeline qw(optimized_pipeline full_pipeline grammars_match bnf_text);
use Chalk::Bootstrap::Target::XS;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Desugar qw(desugar_grammar);
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Grammar::BNF;

my $ir = optimized_pipeline();
ok(defined $ir, 'optimized pipeline produces IR');

my $target = Chalk::Bootstrap::Target::XS->new();
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
    eval { require Chalk::Grammar::BNF::Rules };
    is($@, '', 'Chalk::Grammar::BNF::Rules loads without error') or diag $@;
}

# === Verify XS module exposes rule methods ===

{
    my @rule_names = qw(Grammar Rule Alternatives Sequence Element Atom Quantifier Comment Identifier InlineRegex);
    for my $name (@rule_names) {
        ok(Chalk::Grammar::BNF::Rules->can($name), "XS module has $name method");
    }
}

# === Call each rule method and build grammar array ===

my @xs_rules;
{
    my @rule_names = qw(Grammar Rule Alternatives Sequence Element Atom Quantifier Comment Identifier InlineRegex);
    for my $name (@rule_names) {
        my $rule = eval { Chalk::Grammar::BNF::Rules->$name() };
        is($@, '', "calling $name() succeeds") or diag $@;
        isa_ok($rule, 'Chalk::Grammar::Rule', "$name() returns a Rule object");
        push @xs_rules, $rule if defined $rule;
    }
}

# === Three-way recognizer equivalence ===

# M0: Hand-written grammar
my $m0_grammar = Chalk::Grammar::BNF::grammar();
ok(defined $m0_grammar, 'M0: hand-written grammar loaded');
is(scalar $m0_grammar->@*, 10, 'M0: 10 rules');

# M4: Generated Perl grammar
my $perl_target = Chalk::Bootstrap::Target::Perl->new();
my $perl_code = $perl_target->generate($ir);
# Use a distinct class name to avoid collision with bootstrap-validation.t
$perl_code =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::BNF::XSTestGenerated/g;
eval $perl_code;
is($@, '', 'M4: generated Perl evals without error') or diag $@;
my $m4_grammar = Chalk::Grammar::BNF::XSTestGenerated::grammar();
ok(defined $m4_grammar, 'M4: Perl-generated grammar loaded');
is(scalar $m4_grammar->@*, 10, 'M4: 10 rules');

# M5: XS-generated grammar (built from individual rule method calls)
is(scalar @xs_rules, 10, 'M5: XS-generated grammar has 10 rules');

# Pairwise equivalence
ok(grammars_match($m0_grammar, $m4_grammar), 'M0 == M4: hand-written matches Perl-generated');
ok(grammars_match($m0_grammar, \@xs_rules), 'M0 == M5: hand-written matches XS-generated');
ok(grammars_match($m4_grammar, \@xs_rules), 'M4 == M5: Perl-generated matches XS-generated');

# === Recognizer acceptance/rejection ===

# Build Earley parsers from each grammar implementation
my @grammars = (
    ['M0 (hand-written)' => $m0_grammar],
    ['M4 (Perl-generated)' => $m4_grammar],
    ['M5 (XS-generated)' => \@xs_rules],
);

for my $pair (@grammars) {
    my ($label, $grammar) = $pair->@*;
    my $desugared = desugar_grammar($grammar);
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $bool_sr,
    );

    ok($parser->parse("Identifier ::= /[A-Za-z]+/ ;"),
        "$label: accepts simple rule");
    ok($parser->parse("Atom ::= Identifier | InlineRegex ;"),
        "$label: accepts rule with alternatives");
    ok(!$parser->parse("not valid BNF"),
        "$label: rejects invalid input");
}

# === Full BNF meta-grammar parse through each recognizer ===
# This exercises the whitespace regex, quantifier terminals, and inline regex
# patterns — the values most affected by the newSVpvn length bug.

{
    my $bnf = bnf_text();
    for my $pair (@grammars) {
        my ($label, $grammar) = $pair->@*;
        my $desugared = desugar_grammar($grammar);
        my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
        my $parser = Chalk::Bootstrap::Earley->new(
            grammar  => $desugared,
            semiring => $bool_sr,
        );

        ok($parser->parse($bnf),
            "$label: accepts full 10-rule BNF meta-grammar");
    }
}

done_testing();
