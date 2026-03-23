# ABOUTME: End-to-end integration test for the chalk.so C codegen pipeline.
# ABOUTME: Loads all 7 C-backed classes in a subprocess and runs a real Earley parse.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use Cwd qw(abs_path);
use Config;

my $so_ext    = $Config{dlext};
my $repo_root = abs_path(dirname(__FILE__) . '/../..');
my $build_dir = "$repo_root/.build/chalk-so-gen";
my $chalk_so  = "$build_dir/chalk.$so_ext";
my $perl      = $^X;

# All 7 classes that should be in chalk.so
my @classes = (
    { pkg => 'Chalk::Bootstrap::Semiring::Boolean',         slug => 'boolean' },
    { pkg => 'Chalk::Bootstrap::Semiring::Structural',       slug => 'structural' },
    { pkg => 'Chalk::Bootstrap::Semiring::SemanticAction',   slug => 'semanticaction' },
    { pkg => 'Chalk::Bootstrap::Semiring::FilterComposite',  slug => 'filtercomposite' },
    { pkg => 'Chalk::Bootstrap::Semiring::Precedence',       slug => 'precedence' },
    { pkg => 'Chalk::Bootstrap::Semiring::TypeInference',    slug => 'typeinference' },
    { pkg => 'Chalk::Bootstrap::Earley',                     slug => 'earley' },
);

# Derive the per-class .so path from the package name
sub class_so_path($pkg) {
    my $pkg_path = $pkg =~ s{::}{/}gr;
    my $base     = ($pkg =~ /(\w+)$/)[0];
    return "$build_dir/auto/$pkg_path/$base.$so_ext";
}

# Check prerequisites — skip if build hasn't been run
plan skip_all => "chalk.so not built (run script/build-chalk-so-generated first)"
    unless -f $chalk_so;

for my $c (@classes) {
    my $so = class_so_path($c->{pkg});
    plan skip_all => "$c->{pkg} .so not found at $so (rebuild with script/build-chalk-so-generated)"
        unless -f $so;
}

# Build a temporary blib layout with stub .pm files for all classes.
# Each stub loads its .so via dl_install_xsub (not XSLoader, which breaks
# class_setup_stash by adding DynaLoader to @ISA).
my $tmpdir   = tempdir(CLEANUP => 1);
my $blib_lib = "$tmpdir/blib/lib";

for my $c (@classes) {
    my $pkg      = $c->{pkg};
    my $so_path  = class_so_path($pkg);
    my $pkg_path = $pkg =~ s{::}{/}gr;
    my $base     = ($pkg =~ /(\w+)$/)[0];

    # Copy .so into blib/arch
    my $arch_dir = "$tmpdir/blib/arch/auto/$pkg_path";
    make_path($arch_dir);
    copy($so_path, "$arch_dir/$base.$so_ext")
        or die "copy $base.$so_ext failed: $!";

    # Write stub .pm
    my $pm_dir = "$blib_lib/" . ($pkg =~ s{::[^:]+$}{}r =~ s{::}{/}gr);
    make_path($pm_dir);
    my $pm_file = "$blib_lib/${pkg_path}.pm";
    my $boot_sym = "boot_" . ($pkg =~ s/::/__/gr);

    open my $fh, '>', $pm_file or die "Cannot write $pm_file: $!";
    print $fh <<"END_PM";
package $pkg;
use strict;
use warnings;
require DynaLoader;

my \$so;
for my \$dir (\@INC) {
    next if ref \$dir;
    my \$path = "\$dir/auto/$pkg_path/$base.$so_ext";
    if (-f \$path) { \$so = \$path; last; }
}
die "Cannot locate $base.$so_ext in \@INC" unless defined \$so;

my \$libref = DynaLoader::dl_load_file(\$so, 0)
    or die "dl_load_file $base: " . DynaLoader::dl_error();
my \$boot = DynaLoader::dl_find_symbol(\$libref, "$boot_sym")
    or die "dl_find_symbol $boot_sym: " . DynaLoader::dl_error();
DynaLoader::dl_install_xsub("${pkg}::_bootstrap", \$boot, \$so);
${pkg}->_bootstrap();

1;
END_PM
    close $fh;
}

# Helper: write a subprocess test script, run it, return (stdout, exit_code)
sub run_subprocess($code) {
    my (undef, $script_file) = tempfile(SUFFIX => '.pl', UNLINK => 1, DIR => $tmpdir);
    open my $fh, '>:utf8', $script_file or die "Cannot write $script_file: $!";
    print $fh $code;
    close $fh;
    my $out = `$perl $script_file 2>&1`;
    return ($out, $? >> 8);
}

my $lib_arch    = "use lib '$tmpdir/blib/arch';";
my $lib_pm      = "use lib '$tmpdir/blib/lib';";
my $lib_project = "use lib '$repo_root/lib';";
my $chalk_load  = "require DynaLoader; "
    . "DynaLoader::dl_load_file('$chalk_so', 0x01) "
    . "or die 'chalk.so: ' . DynaLoader::dl_error();";

# =========================================================================
# Part 1: Load all 7 C-backed classes and verify instantiation
# =========================================================================

my ($out1, $exit1) = run_subprocess(<<"END_SCRIPT");
use 5.42.0;
use utf8;
$lib_arch
$lib_pm
$lib_project
$chalk_load

# Load all C-backed classes in dependency order
require Chalk::Bootstrap::Semiring::Boolean;
require Chalk::Bootstrap::Semiring::Structural;
require Chalk::Bootstrap::Semiring::SemanticAction;
require Chalk::Bootstrap::Semiring::Precedence;
require Chalk::Bootstrap::Semiring::TypeInference;
require Chalk::Bootstrap::Semiring::FilterComposite;
require Chalk::Bootstrap::Earley;

# Instantiate Boolean
my \$bool = Chalk::Bootstrap::Semiring::Boolean->new();
print defined(\$bool) ? 'BOOL_OK' : 'BOOL_FAIL';
print "\\n";

# Verify Boolean operations
print \$bool->is_zero(\$bool->zero()) ? 'BOOL_ZERO_OK' : 'BOOL_ZERO_FAIL';
print "\\n";
print !\$bool->is_zero(\$bool->one()) ? 'BOOL_ONE_OK' : 'BOOL_ONE_FAIL';
print "\\n";

print 'LOAD_ALL_OK';
print "\\n";
END_SCRIPT

is($exit1, 0, 'Part 1: subprocess loads all 7 classes without error')
    or diag("Part 1 output:\n$out1");

like($out1, qr/BOOL_OK/,      'Part 1: Boolean instantiated');
like($out1, qr/BOOL_ZERO_OK/, 'Part 1: Boolean zero works');
like($out1, qr/BOOL_ONE_OK/,  'Part 1: Boolean one works');
like($out1, qr/LOAD_ALL_OK/,  'Part 1: all 7 classes loaded successfully');

# =========================================================================
# Part 2: Parse with C-backed Boolean + pure-Perl Earley
# =========================================================================

my ($out2, $exit2) = run_subprocess(<<"END_SCRIPT");
use 5.42.0;
use utf8;
$lib_arch
$lib_pm
$lib_project
$chalk_load

require Chalk::Bootstrap::Semiring::Boolean;
require Chalk::Grammar::Symbol;
require Chalk::Grammar::Rule;
require Chalk::Bootstrap::Earley;

# Simple grammar: Start -> 'a' 'b'
my \$grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'Start',
        expressions => [[
            Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a'),
            Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b'),
        ]],
    ),
];

my \$semiring = Chalk::Bootstrap::Semiring::Boolean->new();
my \$parser   = Chalk::Bootstrap::Earley->new(
    grammar  => \$grammar,
    semiring => \$semiring,
);

print \$parser->parse('ab')   ? 'ACCEPT_AB' : 'REJECT_AB';
print "\\n";
print !\$parser->parse('a')   ? 'REJECT_A'  : 'ACCEPT_A';
print "\\n";
print !\$parser->parse('abc') ? 'REJECT_ABC' : 'ACCEPT_ABC';
print "\\n";
print !\$parser->parse('')    ? 'REJECT_EMPTY' : 'ACCEPT_EMPTY';
print "\\n";

print 'PARSE_BOOL_OK';
print "\\n";
END_SCRIPT

is($exit2, 0, 'Part 2: C Boolean + Earley parse subprocess exits cleanly')
    or diag("Part 2 output:\n$out2");

like($out2, qr/ACCEPT_AB/,     'Part 2: accepts "ab"');
like($out2, qr/REJECT_A/,      'Part 2: rejects "a" (incomplete)');
like($out2, qr/REJECT_ABC/,    'Part 2: rejects "abc" (too long)');
like($out2, qr/REJECT_EMPTY/,  'Part 2: rejects empty string');
like($out2, qr/PARSE_BOOL_OK/, 'Part 2: Boolean parse complete');

# =========================================================================
# Part 3: Parse with C-backed FilterComposite (full 5-ary semiring)
# The real production path: FilterComposite wraps all 5 semirings.
# =========================================================================

my ($out3, $exit3) = run_subprocess(<<"END_SCRIPT");
use 5.42.0;
use utf8;
$lib_arch
$lib_pm
$lib_project
$chalk_load

# Load C-backed semirings
require Chalk::Bootstrap::Semiring::Boolean;
require Chalk::Bootstrap::Semiring::Structural;
require Chalk::Bootstrap::Semiring::SemanticAction;
require Chalk::Bootstrap::Semiring::Precedence;
require Chalk::Bootstrap::Semiring::TypeInference;
require Chalk::Bootstrap::Semiring::FilterComposite;

# Load grammar and parser (pure Perl Earley — not C-backed for this test)
require Chalk::Grammar::Symbol;
require Chalk::Grammar::Rule;
require Chalk::Bootstrap::Earley;

# Build a small grammar: Expr -> 'a' | 'a' '+' 'a'
my \$grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'Expr',
        expressions => [
            [Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a')],
            [
                Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\\\+'),
                Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a'),
            ],
        ],
    ),
];

# Build FilterComposite from 5 component semirings
my \$bool   = Chalk::Bootstrap::Semiring::Boolean->new();
my \$struct = Chalk::Bootstrap::Semiring::Structural->new();
my \$sa     = Chalk::Bootstrap::Semiring::SemanticAction->new();
my \$prec   = Chalk::Bootstrap::Semiring::Precedence->new(lookup => {});
my \$ti     = Chalk::Bootstrap::Semiring::TypeInference->new(
    keyword_check  => sub { false },
    builtin_lookup => sub { undef },
);

my \$fc = Chalk::Bootstrap::Semiring::FilterComposite->new(
    semirings => [\$bool, \$prec, \$ti, \$struct, \$sa],
);

my \$parser = Chalk::Bootstrap::Earley->new(
    grammar  => \$grammar,
    semiring => \$fc,
);

# Parse "a" (should be accepted via alt 1)
my \$r1 = \$parser->parse('a');
print defined(\$r1) && \$r1 ? 'FC_ACCEPT_A' : 'FC_REJECT_A';
print "\\n";

# Parse "a+a" (should be accepted via alt 2)
my \$r2 = \$parser->parse('a+a');
print defined(\$r2) && \$r2 ? 'FC_ACCEPT_APA' : 'FC_REJECT_APA';
print "\\n";

# Parse "b" (should be rejected)
my \$r3 = \$parser->parse('b');
print !defined(\$r3) || !\$r3 ? 'FC_REJECT_B' : 'FC_ACCEPT_B';
print "\\n";

print 'FC_PARSE_OK';
print "\\n";
END_SCRIPT

is($exit3, 0, 'Part 3: FilterComposite + Earley subprocess exits cleanly')
    or diag("Part 3 output:\n$out3");

like($out3, qr/FC_ACCEPT_A/,   'Part 3: FilterComposite accepts "a"');
like($out3, qr/FC_ACCEPT_APA/, 'Part 3: FilterComposite accepts "a+a"');
like($out3, qr/FC_REJECT_B/,   'Part 3: FilterComposite rejects "b"');
like($out3, qr/FC_PARSE_OK/,   'Part 3: FilterComposite parse complete');

# =========================================================================
# Part 4: Full Perl grammar pipeline — parse a real .pm file
# Uses C-backed semirings (all 7 classes) + full 65-rule Perl grammar.
# This is the production path: BNF → grammar → desugar → FilterComposite → parse
# =========================================================================

my $lib_test = "use lib '$repo_root/t/bootstrap/lib';";

# Target: Boolean.pm (68 lines) — small but real Perl with class syntax
my $target_file = "$repo_root/lib/Chalk/Bootstrap/Semiring/Boolean.pm";

my ($out4, $exit4) = run_subprocess(<<"END_SCRIPT");
use 5.42.0;
use utf8;
use Time::HiRes qw(time);
\$| = 1;
$lib_arch
$lib_pm
$lib_project
$lib_test
$chalk_load

# Load all 7 C-backed classes
require Chalk::Bootstrap::Semiring::Boolean;
require Chalk::Bootstrap::Semiring::Structural;
require Chalk::Bootstrap::Semiring::SemanticAction;
require Chalk::Bootstrap::Semiring::Precedence;
require Chalk::Bootstrap::Semiring::TypeInference;
require Chalk::Bootstrap::Semiring::FilterComposite;
require Chalk::Bootstrap::Earley;

say "LOADED_OK";

# Build grammar from BNF pipeline
my \$t0 = time();
require TestPipeline;
my \$raw_ir = TestPipeline::perl_pipeline();
die "perl_pipeline returned undef" unless defined \$raw_ir;

require Chalk::Bootstrap::BNF::Target::Perl;
my \$bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my \$generated = \$bnf_target->generate(\$raw_ir);
\$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CEndToEnd/g;
eval "\$generated; 1" or die "Grammar eval: \$\@";
no strict 'refs';
my \$gen_grammar = "Chalk::Grammar::Perl::CEndToEnd::grammar"->();
use strict 'refs';
printf "GRAMMAR_OK %.1fs %d\\n", time() - \$t0, scalar \@\$gen_grammar;

# Reorder (Program first) and desugar
my \@ordered;
my \@rest;
for my \$rule (\@\$gen_grammar) {
    if (\$rule->name() eq 'Program') { unshift \@ordered, \$rule }
    else { push \@rest, \$rule }
}
push \@ordered, \@rest;

require Chalk::Bootstrap::Desugar;
my \$desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\\\@ordered);

# Build parser with C-backed semirings
\$t0 = time();
require Chalk::Grammar::Perl::PrecedenceTable;
require Chalk::Grammar::Perl::KeywordTable;
require Chalk::Grammar::Perl::TypeLibrary;
require Chalk::Bootstrap::Perl::Actions;

my \$fc = Chalk::Bootstrap::Semiring::FilterComposite->new(
    semirings => [
        Chalk::Bootstrap::Semiring::Boolean->new(),
        Chalk::Bootstrap::Semiring::Precedence->new(
            lookup => \\&Chalk::Grammar::Perl::PrecedenceTable::lookup,
        ),
        Chalk::Bootstrap::Semiring::TypeInference->new(
            keyword_check  => \\&Chalk::Grammar::Perl::KeywordTable::is_keyword,
            builtin_lookup => \\&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
        ),
        Chalk::Bootstrap::Semiring::Structural->new(),
        Chalk::Bootstrap::Semiring::SemanticAction->new(
            actions => Chalk::Bootstrap::Perl::Actions->new(),
        ),
    ],
);

my \$parser = Chalk::Bootstrap::Earley->new(
    grammar  => \$desugared,
    semiring => \$fc,
);
printf "PARSER_OK %.1fs\\n", time() - \$t0;

# Parse the target file
my \$target = '$target_file';
open my \$fh, '<:utf8', \$target or die "Cannot read \$target: \$!";
local \$/;
my \$source = <\$fh>;
close \$fh;
my \$lines = (\$source =~ tr/\\n//) + 1;
printf "PARSING %d %d\\n", \$lines, length(\$source);

\$t0 = time();
my \$result = \$parser->parse_value(\$source);
my \$elapsed = time() - \$t0;

if (defined \$result) {
    printf "PARSE_OK %.1f %.0f\\n", \$elapsed, \$lines / \$elapsed;
} else {
    printf "PARSE_FAILED %.1f\\n", \$elapsed;
}
END_SCRIPT

is($exit4, 0, 'Part 4: Full grammar pipeline subprocess exits cleanly')
    or diag("Part 4 output:\n$out4");

like($out4, qr/LOADED_OK/,   'Part 4: all C-backed classes loaded');
like($out4, qr/GRAMMAR_OK/,  'Part 4: Perl grammar built from BNF');
like($out4, qr/PARSER_OK/,   'Part 4: FilterComposite parser constructed');
like($out4, qr/PARSE_OK/,    'Part 4: Boolean.pm parsed successfully')
    or diag("Part 4 full output:\n$out4");

# Extract timing from Part 4 output
if ($out4 =~ /PARSE_OK (\S+) (\S+)/) {
    diag("Part 4 performance: ${1}s, $2 lines/sec");
}

done_testing;
