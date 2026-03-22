# ABOUTME: Targeted segfault diagnostic for full-semiring XS parse.
# ABOUTME: Tests individual semiring callbacks in XS before full parse to isolate crash.
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

diag "Phase 1: Setting up grammar pipeline...";
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSSeg1') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

diag "Phase 2: Parsing Earley.pm to IR...";
my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm') };
ok(defined $ir, 'Earley.pm parses to IR') or BAIL_OUT("Parse failed: $@");

diag "Phase 3: Generating XS distribution...";
my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSSeg1',
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

# Save XS for inspection
for my $path (sort keys $dist->%*) {
    if ($path =~ /\.xs$/) {
        open(my $xfh, '>', "/tmp/earley_seg.xs") or warn "Cannot save XS: $!";
        if ($xfh) { print $xfh $dist->{$path}; close $xfh; }
        last;
    }
}

diag "Phase 4: Compiling XS...";
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
eval { require Test::XSSeg1 };
is($@, '', 'XS module loads') or BAIL_OUT("Load failed: $@");

# Build Perl grammar
diag "Phase 5: Building Perl grammar...";
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $perl_ir = perl_pipeline();
my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($perl_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSSeg1Grammar/g;
eval $generated;
is($@, '', 'grammar compiles') or BAIL_OUT("Grammar compile failed: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSSeg1Grammar::grammar();
my @ordered = sort {
    ($a->name() eq 'Program' ? 0 : 1) <=> ($b->name() eq 'Program' ? 0 : 1)
} $gen_grammar->@*;
my $desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@ordered);

# Build semirings
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

my $tiny = 'use 5.42.0;';

# --- Test 1: Full semiring with Perl Earley (sanity check) ---
{
    my $perl_fc = build_full_semiring();
    my $perl_earley = Chalk::Bootstrap::Earley->new(
        grammar => $desugared, semiring => $perl_fc,
    );
    $perl_fc->reset_cache();
    my $perl_result = $perl_earley->parse($tiny);
    ok($perl_result, "Perl Earley parses '$tiny' with full semiring");
}

# --- Test 2: XS Boolean only (should work) ---
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $xs_bool = Test::XSSeg1->new(grammar => $desugared, semiring => $bool_sr);
    my $r = eval { $xs_bool->parse($tiny) };
    ok($r, "XS Boolean parses '$tiny'") or diag "Error: $@";
}

# --- Test 3: Progressive semiring tests in fork ---
# Test with each semiring individually, then composite

my @semiring_tests = (
    ['Boolean only', sub {
        Chalk::Bootstrap::Semiring::Boolean->new()
    }],
    ['Precedence only', sub {
        Chalk::Bootstrap::Semiring::Precedence->new(
            lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
        )
    }],
    ['TypeInference only', sub {
        Chalk::Bootstrap::Semiring::TypeInference->new(
            keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
            builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
        )
    }],
    ['Structural only', sub {
        Chalk::Bootstrap::Semiring::Structural->new()
    }],
    ['SemanticAction only', sub {
        Chalk::Bootstrap::Semiring::SemanticAction->new(
            actions => Chalk::Bootstrap::ConciseTree::Actions->new(),
        )
    }],
    ['FilterComposite [Bool,Prec]', sub {
        Chalk::Bootstrap::Semiring::FilterComposite->new(
            semirings => [
                Chalk::Bootstrap::Semiring::Boolean->new(),
                Chalk::Bootstrap::Semiring::Precedence->new(
                    lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
                ),
            ],
        )
    }],
    ['FilterComposite [Bool,Prec,Type]', sub {
        Chalk::Bootstrap::Semiring::FilterComposite->new(
            semirings => [
                Chalk::Bootstrap::Semiring::Boolean->new(),
                Chalk::Bootstrap::Semiring::Precedence->new(
                    lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
                ),
                Chalk::Bootstrap::Semiring::TypeInference->new(
                    keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
                    builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
                ),
            ],
        )
    }],
    ['Full 5-ary FilterComposite', sub {
        build_full_semiring()
    }],
);

for my $test (@semiring_tests) {
    my ($label, $builder) = $test->@*;

    pipe(my $rd, my $wr) or die "pipe: $!";
    my $pid = fork();
    if ($pid == 0) {
        close $rd;
        $SIG{ALRM} = sub { print $wr "TIMEOUT\n"; close $wr; exit 124; };
        alarm(30);

        my $sr = $builder->();
        my $xs_earley = Test::XSSeg1->new(
            grammar => $desugared, semiring => $sr,
        );
        $sr->reset_cache() if $sr->can('reset_cache');

        # First try: just _make_item with one()
        my $start_rule = $desugared->[0];
        my $one = $sr->one();
        my $item = eval { $xs_earley->_make_item($start_rule, 0, 0, 0, $one) };
        if (!defined $item) {
            print $wr "FAIL_MAKE_ITEM: $@\n";
            close $wr;
            exit 1;
        }
        print $wr "make_item: OK core_id=" . ($item->{core_id} // 'undef') . "\n";

        # Second try: _run_parse
        my $raw = eval { $xs_earley->_run_parse($tiny) };
        if (!defined $raw) {
            print $wr "FAIL_RUN_PARSE: $@\n";
            close $wr;
            exit 1;
        }
        print $wr "run_parse: OK type=" . (ref($raw) || "'$raw'") . "\n";

        # Third try: full parse
        $sr->reset_cache() if $sr->can('reset_cache');
        my $result = eval { $xs_earley->parse($tiny) };
        if ($result) {
            print $wr "OK\n";
        } else {
            print $wr "FAIL_PARSE: $@\n";
        }
        close $wr;
        exit($result ? 0 : 1);
    }
    close $wr;
    my $child_out = do { local $/; <$rd> };
    close $rd;
    waitpid($pid, 0);
    my $sig = $? & 127;
    my $exit = $? >> 8;

    if ($sig) {
        TODO: {
            local $TODO = "XS segfault with $label";
            ok(false, "XS parses '$tiny' with $label");
        }
        diag "  SIGNAL $sig (segfault)";
        diag "  Child output: $child_out" if $child_out;
    } elsif ($exit == 124) {
        TODO: {
            local $TODO = "XS timeout with $label";
            ok(false, "XS parses '$tiny' with $label");
        }
        diag "  TIMEOUT";
    } elsif ($child_out =~ /^OK/m) {
        pass("XS parses '$tiny' with $label");
        diag "  $child_out" if $child_out;
    } else {
        TODO: {
            local $TODO = "XS failure with $label" if $label =~ /FilterComposite|Full/;
            ok(false, "XS parses '$tiny' with $label");
        }
        diag "  Exit: $exit";
        diag "  Output: $child_out" if $child_out;
    }
}

done_testing;
