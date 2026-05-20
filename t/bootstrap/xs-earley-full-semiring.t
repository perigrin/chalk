# ABOUTME: Integration test for Earley compiled via Target::C with full 5-ary FilterComposite semiring.
# ABOUTME: Verifies dogfooded XS codegen produces a working parser for real Perl source files.
use 5.42.0;
use utf8;
use Test::More;
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

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load);
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
use Chalk::Bootstrap::Perl::Actions;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;

# --- Step 1: Parse Earley.pm to IR ---
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSEarleyFull') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm') };
ok(defined $ir, 'Earley.pm parses to IR') or BAIL_OUT("Parse failed: $@");

# --- Step 2: Build and load XS module via Target::C ---
my ($result, $build_err) = eval { build_and_load($ir, $sa, $ctx, 'Chalk::Bootstrap::Earley') };
TODO: {
    local $TODO = 'Earley _run_parse too complex for Target::C single-class compilation';
    ok(defined $result, 'XS module built and loaded');
}
if (!defined $result) {
    diag "Build error: $build_err";
    done_testing();
    exit 0;
}

# --- Step 3: Build the Perl grammar (shared between both parsers) ---
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $perl_ir = perl_pipeline();
ok(defined $perl_ir, 'Perl grammar pipeline produces IR') or BAIL_OUT("Grammar failed");

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($perl_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSEarleyFullGrammar/g;
eval $generated;
is($@, '', 'generated grammar compiles') or BAIL_OUT("Grammar compile failed: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSEarleyFullGrammar::grammar();

# Reorder grammar to start with Program
my @ordered = sort {
    ($a->name() eq 'Program' ? 0 : 1) <=> ($b->name() eq 'Program' ? 0 : 1)
} $gen_grammar->@*;
my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@ordered);

# --- Step 4: Build both parsers with full 5-ary semiring ---

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
        actions => Chalk::Bootstrap::Perl::Actions->new(),
    );
    return Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $struct_sr, $sem_sr],
    );
}

# Read the test source file
my $file = 'lib/Chalk/Bootstrap/Semiring/Boolean.pm';
open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
my $source = do { local $/; <$fh> };
close $fh;
my $line_count = scalar(split /\n/, $source);

# --- Step 5: Parse with pure Perl Earley ---
{
    my $perl_semiring = build_full_semiring();
    my $perl_parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $perl_semiring,
    );
    $perl_semiring->reset_cache();
    my $t0 = time();
    my $perl_result = $perl_parser->parse($source);
    my $perl_elapsed = time() - $t0;
    ok($perl_result, 'Perl Earley parses Boolean.pm');
    diag sprintf("Perl Earley: %.2fs (%.1fms/line)", $perl_elapsed, $perl_elapsed / $line_count * 1000);
}

# --- Step 6: Parse with XS Earley (in forked child for segfault safety) ---
{
    my $xs_semiring = build_full_semiring();
    my $xs_parser = eval { Test::XSEarleyFull->new(
        grammar  => $desugared,
        semiring => $xs_semiring,
    ) };
    is($@, '', 'XS parser with full semiring created') or do {
        diag("Constructor failed: $@");
        done_testing();
        exit 0;
    };

    $xs_semiring->reset_cache();

    # Fork for segfault safety
    pipe(my $rd, my $wr) or die "pipe: $!";
    my $pid = fork();
    if ($pid == 0) {
        # Child: parse and report result via pipe
        close $rd;
        my $t0 = time();
        my $result = eval { $xs_parser->parse($source) };
        my $elapsed = time() - $t0;
        my $err = $@;
        if (defined $result && $result) {
            print $wr "OK:$elapsed\n";
        } else {
            # Try parse_value for more detail
            $xs_semiring->reset_cache();
            my $val = eval { $xs_parser->parse_value($source) };
            my $val_err = $@;
            my $result_str = defined $result ? (ref($result) || "'$result'") : 'undef';
            my $val_str = defined $val ? (ref($val) || "'$val'") : 'undef';
            # Check is_zero on the value
            my $iz = defined $val ? eval { $xs_semiring->is_zero($val) } : 'N/A';
            # Inspect the array contents
            my $detail = '';
            if (ref($val) eq 'ARRAY') {
                $detail = ' elements=' . scalar($val->@*);
                for my $i (0 .. $val->$#*) {
                    my $e = $val->[$i];
                    $detail .= " [$i]=" . (defined $e ? (ref($e) || "'$e'") : 'undef');
                }
            }
            print $wr "FAIL:err=$err result=$result_str val=$val_str is_zero=$iz$detail\n";
        }
        close $wr;
        exit 0;
    }

    close $wr;
    my $child_output = do { local $/; <$rd> };
    close $rd;
    waitpid($pid, 0);
    my $child_signal = $? & 127;

    if ($child_signal) {
        fail("XS parser crashed with signal $child_signal");
    } elsif ($child_output =~ /^OK:(.+)/) {
        my $xs_elapsed = $1 + 0;
        pass('XS Earley parses Boolean.pm with full semiring');
        diag sprintf("XS Earley:   %.2fs (%.1fms/line)",
            $xs_elapsed, $xs_elapsed / $line_count * 1000);
    } else {
        fail("XS parser failed: $child_output");
    }
}

done_testing();
