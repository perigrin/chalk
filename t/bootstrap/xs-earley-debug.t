# ABOUTME: Diagnostic test for XS Earley full-semiring parse failure.
# ABOUTME: Isolates the root cause of _run_parse breaking with 5-ary FilterComposite.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);

use lib 'lib';
use lib 't/bootstrap/lib';

# Skip guards
my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
plan skip_all => 'No C compiler available' unless $have_compiler;
eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

use Chalk::Bootstrap::Perl::Target::XS;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
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

# --- Step 1: Generate and compile XS Earley ---
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSDbg3') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm') };
ok(defined $ir, 'Earley.pm parses to IR') or BAIL_OUT("Parse failed: $@");

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSDbg3',
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
my $dist = eval { $xs->generate_distribution_with_cfg($ir, $sa, $ctx) };
ok(ref($dist) eq 'HASH', 'XS distribution generated') or BAIL_OUT("XS gen failed: $@");

# Save generated XS for post-mortem inspection
for my $path (sort keys $dist->%*) {
    if ($path =~ /\.xs$/) {
        open(my $xfh, '>', "/tmp/earley_full.xs") or warn "Cannot save XS: $!";
        if ($xfh) { print $xfh $dist->{$path}; close $xfh; }
        last;
    }
}

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
    is($? >> 8, 0, 'perl Build.PL') or BAIL_OUT("Build.PL failed: $output");
}
{
    my $libs = join(':', 'lib', $ENV{PERL5LIB} // '');
    my $output = `cd "$tmpdir" && PERL5LIB="$libs" "$^X" Build 2>&1`;
    is($? >> 8, 0, './Build compiles') or BAIL_OUT("Build failed: $output");
}

unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
eval { require Test::XSDbg3 };
is($@, '', 'XS module loads') or BAIL_OUT("Load failed: $@");

# --- Step 2: Build the Perl grammar ---
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $perl_ir = perl_pipeline();
my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($perl_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSDbg3Grammar/g;
eval $generated;
is($@, '', 'grammar compiles') or BAIL_OUT("Grammar compile failed: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSDbg3Grammar::grammar();
my @ordered = sort {
    ($a->name() eq 'Program' ? 0 : 1) <=> ($b->name() eq 'Program' ? 0 : 1)
} $gen_grammar->@*;
my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@ordered);

# --- Step 3: Build semirings ---
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

# --- Step 4: Test Boolean-only XS parse ---
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $xs_bool = Test::XSDbg3->new(grammar => $desugared, semiring => $bool_sr);
    my $tiny = 'use 5.42.0;';
    # Use Carp for better stack trace
    local $SIG{__DIE__} = sub {
        require Carp;
        diag "DIE handler: " . Carp::longmess($_[0]);
    };
    # First test: does Perl Boolean parse work?
    my $perl_bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $perl_bool = Chalk::Bootstrap::Earley->new(
        grammar => $desugared, semiring => $perl_bool_sr,
    );
    my $perl_raw = eval { $perl_bool->_run_parse($tiny) };
    diag "Perl _run_parse returned: " . (defined $perl_raw ? "'$perl_raw'" : 'undef') . " err=$@";

    # Now XS — test individual methods first
    diag "XS _symbol_after_dot test:";
    my $start_rule = $desugared->[0];
    my $test_item = eval { $xs_bool->_make_item($start_rule, 0, 0, 0, $bool_sr->one()) };
    diag "  _make_item: " . (defined $test_item ? "OK core_id=" . ($test_item->{core_id} // 'undef') : "FAIL: $@");
    if (defined $test_item) {
        my $sym = eval { $xs_bool->_symbol_after_dot($test_item, 0) };
        diag "  _symbol_after_dot(item, 0): " . (defined $sym ? $sym->value() . " (ref=" . $sym->is_reference() . ")" : "FAIL: $@");
    }

    # Now full parse
    my $raw = eval { $xs_bool->_run_parse($tiny) };
    diag "XS _run_parse returned: " . (defined $raw ? (ref($raw) || "'$raw'") : 'undef') . " err=$@";
    if (defined $raw) {
        diag "  is_zero: " . ($bool_sr->is_zero($raw) ? 'yes' : 'no');
    }
    my $r = eval { $xs_bool->parse($tiny) };
    ok($r, "Boolean XS parses '$tiny'") or diag "Error: $@";
}

# --- Step 5: Compare Perl vs XS with full semiring on tiny input ---
my $tiny = 'use 5.42.0;';
diag "=== Testing: '$tiny' ===";

{
    my $perl_fc = build_full_semiring();
    my $perl_earley = Chalk::Bootstrap::Earley->new(
        grammar => $desugared, semiring => $perl_fc,
    );
    $perl_fc->reset_cache();
    my $perl_result = $perl_earley->parse($tiny);
    ok($perl_result, "Perl Earley parses '$tiny' with full semiring");
}

{
    my $xs_fc = build_full_semiring();
    my $xs_earley = Test::XSDbg3->new(
        grammar => $desugared, semiring => $xs_fc,
    );
    $xs_fc->reset_cache();

    # Verify fields are accessible
    my $g = $xs_earley->grammar();
    diag "XS grammar rules: " . scalar($g->@*);
    diag "XS first rule: " . $g->[0]->name();

    my $s = $xs_earley->semiring();
    diag "XS semiring type: " . ref($s);

    my $one = $s->one();
    diag "one() type: " . ref($one) . " is_zero: " . ($s->is_zero($one) ? 'yes' : 'no');

    # Check one() components
    if (ref($one) eq 'ARRAY') {
        for my $i (0 .. $one->$#*) {
            my $e = $one->[$i];
            diag "  one[$i] = " . (defined $e ? (ref($e) || "'$e'") : 'undef');
        }
    }

    # Try parse in a fork for segfault safety
    pipe(my $rd, my $wr) or die "pipe: $!";
    my $pid = fork();
    if ($pid == 0) {
        close $rd;
        my $result = eval { $xs_earley->parse($tiny) };
        my $err = $@;
        if ($result) {
            print $wr "OK\n";
        } else {
            print $wr "FAIL: err=$err\n";
            # Detailed: try calling individual methods
            $xs_fc->reset_cache();
            # Check _make_item
            my $start_rule = $desugared->[0];
            my $mi = eval { $xs_earley->_make_item($start_rule, 0, 0, 0, $one) };
            print $wr "  _make_item: " . (defined $mi ? 'OK (core_id=' . ($mi->{core_id} // 'undef') . ')' : "ERROR: $@") . "\n";
            # Check _is_complete
            if (defined $mi) {
                my $ic = eval { $xs_earley->_is_complete($mi, 0) };
                print $wr "  _is_complete: " . (defined $ic ? ($ic ? 'true' : 'false') : "ERROR: $@") . "\n";
            }
        }
        close $wr;
        exit 0;
    }
    close $wr;
    my $child_out = do { local $/; <$rd> };
    close $rd;
    waitpid($pid, 0);
    my $sig = $? & 127;

    if ($sig) {
        fail("XS full-semiring parse crashed: signal $sig");
    } elsif ($child_out =~ /^OK/) {
        pass("XS Earley parses '$tiny' with full semiring");
    } else {
        fail("XS full-semiring parse failed");
        diag $child_out;
    }
}

done_testing;
