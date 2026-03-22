# ABOUTME: Benchmark comparing Perl, single-class XS, and multi-class XS Earley parsers.
# ABOUTME: Parses Boolean.pm with all three, reporting wall-clock time and ms/line.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Time::HiRes qw(time);
use Cwd;

use lib 'lib';
use lib 't/bootstrap/lib';

# Skip guards
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

use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Desugar;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::ConciseTree::Actions;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;

# ========================================================================
# Phase A: Build Perl grammar (shared across IR parsing + all benchmark parsers)
# ========================================================================

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $perl_ir = perl_pipeline();
ok(defined $perl_ir, 'Perl grammar pipeline produces IR') or BAIL_OUT("Grammar failed");

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($perl_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSBenchGrammar/g;
eval $generated;
is($@, '', 'generated grammar compiles') or BAIL_OUT("Grammar compile failed: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSBenchGrammar::grammar();
my @ordered = sort {
    ($a->name() eq 'Program' ? 0 : 1) <=> ($b->name() eq 'Program' ? 0 : 1)
} $gen_grammar->@*;
my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@ordered);

# Helper to parse a file to IR using the shared grammar
sub parse_file_to_ir($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $result = $parser->parse_value($source);
    return unless defined $result;

    my $sa = $semiring->semirings()->[4];
    my $sem_ctx = $result->[4];
    return unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return unless defined $ir;

    return ($ir, $sa, $sem_ctx);
}

# Helper to build and install an XS distribution
sub build_xs_dist($dist, $label) {
    my $tmpdir = tempdir(CLEANUP => 1);
    for my $path (sort keys $dist->%*) {
        my $full_path = "$tmpdir/$path";
        my $dir = dirname($full_path);
        make_path($dir) unless -d $dir;
        open(my $wfh, '>:encoding(UTF-8)', $full_path) or die "Cannot write $full_path: $!";
        print $wfh $dist->{$path};
        close $wfh;
    }

    {
        my $output = `cd "$tmpdir" && "$^X" -Ilib Build.PL 2>&1`;
        is($? >> 8, 0, "$label Build.PL") or BAIL_OUT("Build.PL failed: $output");
    }
    {
        my $libs = join(':', 'lib', $ENV{PERL5LIB} // '');
        my $output = `cd "$tmpdir" && PERL5LIB="$libs" "$^X" Build 2>&1`;
        is($? >> 8, 0, "$label ./Build") or do {
            diag "Build failed: $output";
            BAIL_OUT("Build failed");
        };
    }

    unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
    return $tmpdir;
}

# Helper to build full semiring
my sub build_full_semiring() {
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => Chalk::Bootstrap::ConciseTree::Actions->new(),
    );
    return Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $struct_sr, $sem_sr],
    );
}

# Helper: run parse in forked child for segfault/OOM safety, returns elapsed or undef
sub fork_parse($parser_obj, $source_text) {
    pipe(my $rd, my $wr) or die "pipe: $!";
    my $pid = fork();
    if ($pid == 0) {
        close $rd;
        my $t0 = time();
        my $result = eval { $parser_obj->parse($source_text) };
        my $elapsed = time() - $t0;
        if (defined $result && $result) {
            print $wr "OK:$elapsed\n";
        } else {
            print $wr "FAIL:err=$@ result=" . (defined $result ? "'$result'" : 'undef') . "\n";
        }
        close $wr;
        exit 0;
    }

    close $wr;
    my $child_output = do { local $/; <$rd> };
    close $rd;
    waitpid($pid, 0);
    my $child_signal = $? & 127;

    return { signal => $child_signal, output => $child_output };
}

# Load benchmark source file
my $file = 'lib/Chalk/Bootstrap/Semiring/Boolean.pm';
open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
my $source = do { local $/; <$fh> };
close $fh;
my $line_count = scalar(split /\n/, $source);

diag '';
diag '=== Benchmark: Parse Boolean.pm ===';
diag sprintf('Source: %d lines, %d bytes', $line_count, length($source));
diag '';

# ========================================================================
# Phase B: Perl Earley baseline (before any XS loading)
# ========================================================================

{
    my $semiring = build_full_semiring();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $semiring,
    );
    $semiring->reset_cache();

    my $r = fork_parse($parser, $source);
    if ($r->{signal}) {
        fail("Perl Earley crashed with signal $r->{signal}");
    } elsif ($r->{output} =~ /^OK:(.+)/) {
        my $elapsed = $1 + 0;
        pass('Perl Earley parses Boolean.pm');
        diag sprintf('  Perl Earley:       %6.2fs  (%5.1fms/line)',
            $elapsed, $elapsed / $line_count * 1000);
    } else {
        fail("Perl Earley failed: $r->{output}");
    }
}

# ========================================================================
# Phase C: Build and benchmark single-class XS (Earley only)
# ========================================================================

my ($earley_ir, $earley_sa, $earley_ctx) = parse_file_to_ir('lib/Chalk/Bootstrap/Earley.pm');
ok(defined $earley_ir, 'Earley.pm parses to IR') or BAIL_OUT("Parse failed");

my $single_xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSBenchSingle',
    semiring_intrinsics => {
        semiring => {
            components => [
                { type => 'boolean_refaddr' },
                { type => 'hash_valid' },
                { type => 'defined' },
                { type => 'integer_eq', value => -1 },
                { type => 'defined' },
            ],
        },
    },
);
my $single_dist = eval { $single_xs->generate_distribution_with_cfg($earley_ir, $earley_sa, $earley_ctx) };
ok(ref($single_dist) eq 'HASH', 'single-class XS generated')
    or BAIL_OUT("Single-class gen failed: $@");

build_xs_dist($single_dist, 'single-class');
eval { require Test::XSBenchSingle };
is($@, '', 'single-class XS loads') or BAIL_OUT("Load failed: $@");
undef $single_dist;

# Benchmark single-class XS
{
    my $semiring = build_full_semiring();
    my $parser = eval { Test::XSBenchSingle->new(
        grammar  => $desugared,
        semiring => $semiring,
    ) };
    is($@, '', 'single-class XS parser created') or do {
        diag("Constructor failed: $@");
        done_testing();
        exit 0;
    };
    $semiring->reset_cache();

    my $r = fork_parse($parser, $source);
    if ($r->{signal}) {
        fail("Single-class XS crashed with signal $r->{signal}");
    } elsif ($r->{output} =~ /^OK:(.+)/) {
        my $elapsed = $1 + 0;
        pass('Single-class XS Earley parses Boolean.pm');
        diag sprintf('  Single-class XS:   %6.2fs  (%5.1fms/line)',
            $elapsed, $elapsed / $line_count * 1000);
    } else {
        fail("Single-class XS failed: $r->{output}");
    }
}

# ========================================================================
# Phase D: Build and benchmark multi-class XS (Earley + all semirings)
# Runs entirely in a subprocess to avoid OOM — parsing 7 files to IR
# peaks at ~738MB RSS, and Perl doesn't return freed memory to the OS.
# By running in a subprocess, the OS reclaims all memory on exit.
# ========================================================================

{
    my $cwd = Cwd::getcwd();

    # Write subprocess script to a temp file. Uses non-interpolating heredoc
    # to avoid escaping nightmares. The benchmark source file path is passed
    # as a command-line argument ($ARGV[0]).
    require File::Temp;
    my ($script_fh, $script_path) = File::Temp::tempfile(
        'xs-bench-multi-XXXX', SUFFIX => '.pl', TMPDIR => 1, UNLINK => 1,
    );
    print $script_fh <<'END_SCRIPT';
use 5.42.0;
use utf8;
use Time::HiRes qw(time);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);

use lib 'lib';
use lib 't/bootstrap/lib';

sub get_rss_mb() {
    open my $fh, '<', '/proc/self/status' or return 0;
    while (<$fh>) { return $1 / 1024 if /^VmRSS:\s+(\d+)\s+kB/ }
    return 0;
}

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Desugar;
use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::ConciseTree::Actions;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;

my $bench_file = $ARGV[0] or die "Usage: $0 <source-file>\n";

# --- Step 1: Rebuild grammar ---
print STDERR "multi-class: rebuilding grammar...\n";
my $t_start = time();

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $perl_ir = perl_pipeline();
die "Grammar failed" unless defined $perl_ir;

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($perl_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSBenchMultiProc/g;
eval $generated;
die "Grammar compile: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::XSBenchMultiProc::grammar();
my @ordered = sort {
    ($a->name() eq 'Program' ? 0 : 1) <=> ($b->name() eq 'Program' ? 0 : 1)
} $gen_grammar->@*;
my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@ordered);

# Free grammar IR — no longer needed
undef $perl_ir;
undef $generated;
undef $bnf_target;
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

print STDERR sprintf("multi-class: grammar ready (%.1fs, RSS=%.0fMB)\n", time() - $t_start, get_rss_mb());

# --- Step 2: Parse each file to IR ---
my @class_files = (
    ['Chalk::Bootstrap::Semiring::Boolean',         'lib/Chalk/Bootstrap/Semiring/Boolean.pm'],
    ['Chalk::Bootstrap::Semiring::Precedence',      'lib/Chalk/Bootstrap/Semiring/Precedence.pm'],
    ['Chalk::Bootstrap::Semiring::TypeInference',   'lib/Chalk/Bootstrap/Semiring/TypeInference.pm'],
    ['Chalk::Bootstrap::Semiring::Structural',      'lib/Chalk/Bootstrap/Semiring/Structural.pm'],
    ['Chalk::Bootstrap::Semiring::SemanticAction',  'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm'],
    ['Chalk::Bootstrap::Semiring::FilterComposite', 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm'],
    ['Chalk::Bootstrap::Earley',                    'lib/Chalk/Bootstrap/Earley.pm'],
);

sub parse_one_file($grammar_ref, $file_path) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file_path or die "Cannot read $file_path: $!";
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($grammar_ref, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $result = $parser->parse_value($source);
    return unless defined $result;

    my $sa = $semiring->semirings()->[4];
    my $sem_ctx = $result->[4];
    return unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return unless defined $ir;

    # Snapshot cfg_state before subsequent parses wipe it via reset_cache().
    my %cfg_snapshot;
    my @stack = ($sem_ctx);
    while (@stack) {
        my $node = pop @stack;
        my $state = $sa->cfg_state($node);
        if (defined $state) {
            $cfg_snapshot{refaddr($node)} = $state;
        }
        push @stack, $node->children()->@*;
    }

    return ($ir, $sa, $sem_ctx, \%cfg_snapshot);
}

my %parsed;
for my $entry (@class_files) {
    my ($class_name, $class_file) = $entry->@*;
    print STDERR "multi-class: parsing $class_name...\n";
    my ($ir, $sa, $ctx, $cfg_snapshot) = parse_one_file($gen_grammar, $class_file);
    die "Parse failed for $class_name" unless defined $ir;
    $parsed{$class_name} = { ir => $ir, sa => $sa, ctx => $ctx, cfg_snapshot => $cfg_snapshot };
    print STDERR sprintf("multi-class: parsed $class_name OK (RSS=%.0fMB)\n", get_rss_mb());
}

# --- Step 3: Register classes and generate multi-class XS ---
my @semiring_classes = map { $_->[0] } @class_files[0..4];
my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
for my $entry (@class_files) {
    my ($class_name, $class_file) = $entry->@*;
    next if $class_name eq 'Chalk::Bootstrap::Semiring::FilterComposite';
    next if $class_name eq 'Chalk::Bootstrap::Earley';
    $reg->register($class_name, {
        ir => $parsed{$class_name}{ir},
        sa => $parsed{$class_name}{sa},
        ctx => $parsed{$class_name}{ctx},
        uses => [],
    });
}
$reg->register('Chalk::Bootstrap::Semiring::FilterComposite', {
    ir => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{ir},
    sa => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{sa},
    ctx => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{ctx},
    uses => \@semiring_classes,
    composite_components => { semirings => \@semiring_classes },
});
$reg->register('Chalk::Bootstrap::Earley', {
    ir => $parsed{'Chalk::Bootstrap::Earley'}{ir},
    sa => $parsed{'Chalk::Bootstrap::Earley'}{sa},
    ctx => $parsed{'Chalk::Bootstrap::Earley'}{ctx},
    uses => ['Chalk::Bootstrap::Semiring::FilterComposite'],
});

my $multi_xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSBenchMulti',
    class_registry => $reg,
    semiring_intrinsics => {
        semiring => {
            components => [
                { type => 'boolean_refaddr' },
                { type => 'hash_valid' },
                { type => 'defined' },
                { type => 'integer_eq', value => -1 },
                { type => 'defined' },
            ],
        },
    },
    # Reader metadata for classes not in the compilation bundle.
    # Enables ObjectFIELDS inlining instead of call_method for :reader
    # accessors, avoiding "uninitialized value in subroutine entry" warnings
    # with Perl 5.42 feature class readers in deeply nested scopes.
    external_readers => {
        'Chalk::Grammar::Symbol' => { type => 0, value => 1, quantifier => 2 },
        'Chalk::Grammar::Rule'   => { name => 0, expressions => 1 },
    },
);

my @entries = map {
    my $p = $parsed{$_->[0]};
    { class_name => $_->[0], ir => $p->{ir}, sa => $p->{sa}, ctx => $p->{ctx}, cfg_snapshot => $p->{cfg_snapshot} }
} @class_files;

print STDERR "multi-class: generating XS distribution...\n";
my $dist = eval { $multi_xs->generate_distribution_multi_class(\@entries) };
die "Multi-class gen failed: $@" unless ref($dist) eq 'HASH';
print STDERR sprintf("multi-class: XS generated (RSS=%.0fMB)\n", get_rss_mb());

# Report XS stats
my ($xs_key) = grep { /\.xs$/ } keys $dist->%*;
if ($xs_key) {
    my $multi_code = $dist->{$xs_key};
    my @impl = ($multi_code =~ /_impl_/g);
    my @cm = ($multi_code =~ /call_method/g);
    print STDERR sprintf("multi-class: _impl_=%d  call_method=%d  lines=%d\n",
        scalar @impl, scalar @cm, scalar(split /\n/, $multi_code));
}

# --- Step 4: Build XS ---
# CLEANUP => 0 because the parent process needs the blib/ after we exit
my $tmpdir = tempdir(CLEANUP => 0);
for my $path (sort keys $dist->%*) {
    my $full_path = "$tmpdir/$path";
    my $dir = dirname($full_path);
    make_path($dir) unless -d $dir;
    open(my $wfh, '>:encoding(UTF-8)', $full_path) or die "Cannot write $full_path: $!";
    print $wfh $dist->{$path};
    close $wfh;
}

# Free parsed IR and dist before building — no longer needed
undef %parsed;
undef $dist;
undef $reg;
undef $multi_xs;
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
print STDERR sprintf("multi-class: freed IR (RSS=%.0fMB)\n", get_rss_mb());

{
    my $output = `cd "$tmpdir" && "$^X" -Ilib Build.PL 2>&1`;
    die "Build.PL failed: $output" if ($? >> 8) != 0;
}
{
    my $libs = join(':', 'lib', $ENV{PERL5LIB} // '');
    my $output = `cd "$tmpdir" && PERL5LIB="$libs" "$^X" Build 2>&1`;
    die "Build failed: $output" if ($? >> 8) != 0;
}

print STDERR sprintf("multi-class: built OK (%.1fs total, RSS=%.0fMB)\n", time() - $t_start, get_rss_mb());

# Output the temp directory path so the parent can run the benchmark
# in a fresh process after this subprocess exits (freeing ~758MB RSS).
print "TMPDIR:$tmpdir\n";
END_SCRIPT
    close $script_fh;

    # Phase D.1: Run the build subprocess (parse 7 files, generate XS, compile)
    my $build_cmd = qq{"$^X" -Ilib "$script_path" "$file" 2>&1};
    diag "multi-class: running build subprocess (parse+generate+compile)...";
    my $build_output = `cd "$cwd" && $build_cmd`;
    my $build_exit = $? >> 8;
    my $build_signal = $? & 127;

    # Show subprocess diagnostics
    for my $line (split /\n/, $build_output) {
        diag "  $line" if $line =~ /^multi-class:/;
    }

    if ($build_signal) {
        fail("Multi-class XS build subprocess crashed with signal $build_signal");
        diag "Output: $build_output";
    } elsif ($build_exit != 0) {
        fail("Multi-class XS build subprocess failed (exit=$build_exit)");
        diag "Output: $build_output";
    } elsif ($build_output =~ /^TMPDIR:(.+)/m) {
        my $multi_tmpdir = $1;
        pass('multi-class XS built successfully');

        # Phase D.2: Run benchmark in a fresh process. The build subprocess
        # has exited, freeing its ~758MB. This process (the parent) is ~200MB.
        # The benchmark process starts fresh at ~63MB.
        my ($bench_fh, $bench_path) = File::Temp::tempfile(
            'xs-bench-run-XXXX', SUFFIX => '.pl', TMPDIR => 1, UNLINK => 1,
        );
        print $bench_fh <<'BENCH_SCRIPT';
use 5.42.0;
use utf8;
use Time::HiRes qw(time);

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Desugar;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::ConciseTree::Actions;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;

my $bench_file = $ARGV[0] or die "Usage: $0 <source-file>\n";

# Rebuild grammar (~2s, ~73MB)
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $perl_ir = perl_pipeline();
die "Grammar failed" unless defined $perl_ir;

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($perl_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSBenchRun/g;
eval $generated;
die "Grammar compile: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::XSBenchRun::grammar();
my @ordered = sort {
    ($a->name() eq 'Program' ? 0 : 1) <=> ($b->name() eq 'Program' ? 0 : 1)
} $gen_grammar->@*;
my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@ordered);

# Free grammar IR
undef $perl_ir;
undef $generated;
undef $bnf_target;
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

# Load multi-class XS module
require Test::XSBenchMulti;

# Read source
open my $fh, '<:utf8', $bench_file or die "Cannot read $bench_file: $!";
my $source = do { local $/; <$fh> };
close $fh;

# Build semiring and parser
my $semiring = Chalk::Bootstrap::Semiring::FilterComposite->new(
    semirings => [
        Chalk::Bootstrap::Semiring::Boolean->new(),
        Chalk::Bootstrap::Semiring::Precedence->new(
            lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
        ),
        Chalk::Bootstrap::Semiring::TypeInference->new(
            keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
            builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
        ),
        Chalk::Bootstrap::Semiring::Structural->new(),
        Chalk::Bootstrap::Semiring::SemanticAction->new(
            actions => Chalk::Bootstrap::ConciseTree::Actions->new(),
        ),
    ],
);
my $parser = Chalk::Bootstrap::Earley->new(
    grammar  => $desugared,
    semiring => $semiring,
);
$semiring->reset_cache();

my $t0 = time();
my $result = eval { $parser->parse($source) };
my $elapsed = time() - $t0;

if (defined $result && $result) {
    print "OK:$elapsed\n";
} else {
    print "FAIL:err=$@ result=" . (defined $result ? "'$result'" : 'undef') . "\n";
}
BENCH_SCRIPT
        close $bench_fh;

        my $bench_cmd = qq{"$^X" -I"$multi_tmpdir/blib/lib" -I"$multi_tmpdir/blib/arch" -Ilib "$bench_path" "$file" 2>&1};

        diag "multi-class: running benchmark in fresh process...";
        my $bench_output = `cd "$cwd" && $bench_cmd`;
        my $bench_exit = $? >> 8;
        my $bench_signal = $? & 127;

        # Show bench diagnostics
        for my $line (split /\n/, $bench_output) {
            diag "  $line" if $line =~ /^bench:/;
        }

        if ($bench_signal) {
            fail("Multi-class XS benchmark crashed with signal $bench_signal");
            diag "Output: $bench_output";
        } elsif ($bench_output =~ /^OK:(.+)/m) {
            my $elapsed = $1 + 0;
            pass('Multi-class XS Earley parses Boolean.pm');
            diag sprintf('  Multi-class XS:    %6.2fs  (%5.1fms/line)',
                $elapsed, $elapsed / $line_count * 1000);
        } elsif ($bench_output =~ /FAIL/) {
            # XS-compiled on_complete closures (TypeInferenceActions dispatch,
            # CallExpression callback) degrade to eval_pv with stringified
            # captures. The parse runs but produces wrong semiring values.
            TODO: {
                local $TODO = 'XS closure codegen: on_complete anonymous subs lose captures';
                fail('Multi-class XS Earley parses Boolean.pm');
            }
        } else {
            fail("Multi-class XS benchmark failed (exit=$bench_exit)");
            diag "Output: $bench_output";
        }
    } else {
        fail("Multi-class XS build produced no TMPDIR");
        diag "Output: $build_output";
    }
}

diag '';

done_testing();
