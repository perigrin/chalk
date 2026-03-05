# ABOUTME: Benchmark comparing Perl, single-class XS, and multi-class XS Earley parsers.
# ABOUTME: Parses Boolean.pm with all three, reporting wall-clock time and ms/line.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Time::HiRes qw(time);

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
# ========================================================================

my @class_files = (
    ['Chalk::Bootstrap::Semiring::Boolean',         'lib/Chalk/Bootstrap/Semiring/Boolean.pm'],
    ['Chalk::Bootstrap::Semiring::Precedence',      'lib/Chalk/Bootstrap/Semiring/Precedence.pm'],
    ['Chalk::Bootstrap::Semiring::TypeInference',   'lib/Chalk/Bootstrap/Semiring/TypeInference.pm'],
    ['Chalk::Bootstrap::Semiring::Structural',      'lib/Chalk/Bootstrap/Semiring/Structural.pm'],
    ['Chalk::Bootstrap::Semiring::SemanticAction',  'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm'],
    ['Chalk::Bootstrap::Semiring::FilterComposite', 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm'],
    ['Chalk::Bootstrap::Earley',                    'lib/Chalk/Bootstrap/Earley.pm'],
);

# Reuse Earley IR from single-class step; parse only the 6 semiring classes
my %parsed;
$parsed{'Chalk::Bootstrap::Earley'} = { ir => $earley_ir, sa => $earley_sa, ctx => $earley_ctx };
pass('Chalk::Bootstrap::Earley reused from single-class');

for my $entry (@class_files) {
    my ($class_name, $file) = $entry->@*;
    next if $class_name eq 'Chalk::Bootstrap::Earley';
    my ($ir, $sa, $ctx) = parse_file_to_ir($file);
    ok(defined $ir, "$class_name parses") or BAIL_OUT("Parse failed");
    $parsed{$class_name} = { ir => $ir, sa => $sa, ctx => $ctx };
}

# Register classes
my @semiring_classes = map { $_->[0] } @class_files[0..4];
my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
for my $entry (@class_files) {
    my ($class_name, $file) = $entry->@*;
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
);

my @entries = map {
    my $p = $parsed{$_->[0]};
    { class_name => $_->[0], ir => $p->{ir}, sa => $p->{sa}, ctx => $p->{ctx} }
} @class_files;

my $multi_dist = eval { $multi_xs->generate_distribution_multi_class(\@entries) };
ok(ref($multi_dist) eq 'HASH', 'multi-class XS generated')
    or BAIL_OUT("Multi-class gen failed: $@");

# Extract stats from the generated XS file in the distribution
{
    my ($xs_key) = grep { /\.xs$/ } keys $multi_dist->%*;
    if ($xs_key) {
        my $multi_code = $multi_dist->{$xs_key};
        my @impl = ($multi_code =~ /_impl_/g);
        my @cm = ($multi_code =~ /call_method/g);
        diag sprintf("Multi-class: _impl_=%d  call_method=%d  lines=%d",
            scalar @impl, scalar @cm, scalar(split /\n/, $multi_code));
    }
}

build_xs_dist($multi_dist, 'multi-class');
eval { require Test::XSBenchMulti };
is($@, '', 'multi-class XS loads') or BAIL_OUT("Load failed: $@");

# Free heavy data structures before benchmark forks to reduce memory pressure.
# After parsing 7 files to IR, the process uses significant memory.
# Forked children inherit this, so aggressively free what we can.
undef %parsed;
undef $earley_ir;
undef $earley_sa;
undef $earley_ctx;
undef $multi_dist;
undef @entries;
undef $reg;
undef $multi_xs;
undef $perl_ir;
undef $generated;
undef $bnf_target;
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

# Benchmark multi-class XS
# After loading multi-class XS, Earley and semiring methods are overridden,
# so Chalk::Bootstrap::Earley->new creates a parser using multi-class methods.
# TODO: Currently OOMs in forked child after heavy setup phase (~3GB parent).
# Needs dedicated investigation: either reduce parent memory before fork,
# or run multi-class benchmark in a separate process entirely.
TODO: {
    local $TODO = 'multi-class benchmark OOMs after heavy setup phase';
    my $semiring = build_full_semiring();
    my $parser = eval { Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $semiring,
    ) };
    is($@, '', 'multi-class XS parser created') or do {
        done_testing();
        exit 0;
    };
    $semiring->reset_cache();

    my $r = fork_parse($parser, $source);
    if ($r->{signal}) {
        fail("Multi-class XS crashed with signal $r->{signal}");
    } elsif ($r->{output} =~ /^OK:(.+)/) {
        my $elapsed = $1 + 0;
        pass('Multi-class XS Earley parses Boolean.pm');
        diag sprintf('  Multi-class XS:    %6.2fs  (%5.1fms/line)',
            $elapsed, $elapsed / $line_count * 1000);
    } else {
        fail("Multi-class XS failed: $r->{output}");
    }
}

diag '';

done_testing();
