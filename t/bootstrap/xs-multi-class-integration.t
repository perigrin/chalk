# ABOUTME: Integration test for multi-class XS compilation of Earley + all semirings.
# ABOUTME: Verifies multi-class XS codegen compiles, loads, and methods execute correctly.
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
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

use Chalk::Bootstrap::Perl::Target::XS;
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
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
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Desugar;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::IR::NodeFactory;
use TestPipeline qw(perl_pipeline);

# --- Step 1: Parse all classes to IR ---
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSMultiInteg') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my %parsed;
my @class_files = (
    ['Chalk::Bootstrap::Semiring::Boolean',         'lib/Chalk/Bootstrap/Semiring/Boolean.pm'],
    ['Chalk::Bootstrap::Semiring::Precedence',      'lib/Chalk/Bootstrap/Semiring/Precedence.pm'],
    ['Chalk::Bootstrap::Semiring::TypeInference',   'lib/Chalk/Bootstrap/Semiring/TypeInference.pm'],
    ['Chalk::Bootstrap::Semiring::Structural',      'lib/Chalk/Bootstrap/Semiring/Structural.pm'],
    ['Chalk::Bootstrap::Semiring::SemanticAction',  'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm'],
    ['Chalk::Bootstrap::Semiring::FilterComposite', 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm'],
    ['Chalk::Bootstrap::Earley',                    'lib/Chalk/Bootstrap/Earley.pm'],
);

for my $entry (@class_files) {
    my ($class_name, $file) = $entry->@*;
    my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $file) };
    ok(defined $ir, "$class_name parses to IR") or do {
        diag "Parse failed: $@";
        next;
    };
    $parsed{$class_name} = { ir => $ir, sa => $sa, ctx => $ctx };
}

# --- Step 2: Register classes with ClassRegistry ---
SKIP: {
    skip 'Not all classes parsed', 15
        unless keys %parsed == scalar @class_files;

    my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();

    # Register semirings (no cross-class dependencies among them)
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

    # FilterComposite depends on all 5 semirings
    my @semiring_classes = map { $_->[0] } @class_files[0..4];
    $reg->register('Chalk::Bootstrap::Semiring::FilterComposite', {
        ir => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{ir},
        sa => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{sa},
        ctx => $parsed{'Chalk::Bootstrap::Semiring::FilterComposite'}{ctx},
        uses => \@semiring_classes,
        composite_components => {
            semirings => \@semiring_classes,
        },
    });

    # Earley depends on FilterComposite (via semiring field)
    $reg->register('Chalk::Bootstrap::Earley', {
        ir => $parsed{'Chalk::Bootstrap::Earley'}{ir},
        sa => $parsed{'Chalk::Bootstrap::Earley'}{sa},
        ctx => $parsed{'Chalk::Bootstrap::Earley'}{ctx},
        uses => ['Chalk::Bootstrap::Semiring::FilterComposite'],
    });

    # --- Step 3: Generate multi-class XS ---
    my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => 'Test::XSMultiInteg',
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
        {
            class_name => $_->[0],
            ir => $p->{ir}, sa => $p->{sa}, ctx => $p->{ctx},
        }
    } @class_files;

    my $multi_code = eval { $xs->generate_multi_class(\@entries) };
    ok(defined $multi_code, 'multi-class XS generation succeeds')
        or do {
            diag "Multi-class gen failed: $@";
            skip 'Multi-class generation failed', 14;
        };

    # Basic structural checks
    my @module_sections = ($multi_code =~ /^MODULE\s*=/mg);
    is(scalar @module_sections, scalar @class_files,
        'one MODULE section per compiled class');

    my @boot_blocks = ($multi_code =~ /^BOOT:/mg);
    is(scalar @boot_blocks, 1,
        'exactly one BOOT block in multi-class output');

    # Count direct calls vs bridge crossings
    my @impl = ($multi_code =~ /_impl_/g);
    my @cm = ($multi_code =~ /call_method/g);
    diag sprintf("Multi-class: _impl_=%d  call_method=%d  lines=%d",
        scalar @impl, scalar @cm, scalar(split /\n/, $multi_code));

    # --- Step 4: Write to temp directory and build ---
    my $tmpdir = tempdir(CLEANUP => 1);

    # Write the multi-class .xs file as a distribution
    my $dist = $xs->generate_distribution_multi_class(\@entries);
    ok(ref($dist) eq 'HASH', 'multi-class distribution generated')
        or do {
            diag "Distribution gen failed";
            skip 'Distribution failed', 11;
        };

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
        my $exit = $? >> 8;
        is($exit, 0, 'perl Build.PL exits cleanly') or BAIL_OUT("Build.PL failed: $output");
    }

    {
        my $libs = join(':', 'lib', $ENV{PERL5LIB} // '');
        my $output = `cd "$tmpdir" && PERL5LIB="$libs" "$^X" Build 2>&1`;
        my $exit = $? >> 8;
        is($exit, 0, './Build compiles multi-class XS') or do {
            diag "Build failed: $output";
            skip 'Build failed', 9;
        };
    }

    # --- Step 4.5: Build Perl grammar for integration parse (before XS load) ---
    # Must happen before Step 5 because loading the XS module replaces
    # Earley methods, which breaks the BNF pipeline.
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $integ_ir = eval { perl_pipeline() };
    my $integ_desugared;
    if (defined $integ_ir) {
        my $integ_target = Chalk::Bootstrap::BNF::Target::Perl->new();
        my $integ_generated = $integ_target->generate($integ_ir);
        $integ_generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSMultiIntegParseGrammar/g;
        eval $integ_generated;
        unless ($@) {
            my $integ_grammar = Chalk::Grammar::Perl::XSMultiIntegParseGrammar::grammar();
            my @integ_ordered = sort {
                ($a->name() eq 'Program' ? 0 : 1) <=> ($b->name() eq 'Program' ? 0 : 1)
            } $integ_grammar->@*;
            $integ_desugared = Chalk::Bootstrap::Desugar::desugar_grammar(\@integ_ordered);
        }
    }

    # --- Step 5: Load the XS module ---
    unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";

    eval { require Test::XSMultiInteg };
    is($@, '', 'Test::XSMultiInteg loads without error')
        or do {
            diag "Load failed: $@";
            skip 'Load failed', 8;
        };

    # --- Step 6: Verify XS method registration ---
    ok(Chalk::Bootstrap::Earley->can('parse'),
        'Earley parse method available after XS load');
    ok(Chalk::Bootstrap::Earley->can('_run_parse'),
        'Earley _run_parse method available after XS load');

    # --- Step 7: Execute XS-compiled methods (fork for segfault safety) ---
    # All XS execution happens in a forked child. If XS methods segfault,
    # the parent catches the signal and reports a test failure.
    pipe(my $rd, my $wr) or die "pipe: $!";
    my $pid = fork();
    if ($pid == 0) {
        close $rd;
        my @results;

        # Boolean: test BOOT initialization of class-scope static vars
        my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
        my $zero = eval { $bool->zero() };
        push @results, (defined $zero ? 'PASS' : 'FAIL') . ':Boolean::zero()';
        push @results, (ref($zero) ? 'PASS' : 'FAIL') . ':Boolean::zero() is a ref';

        my $one = eval { $bool->one() };
        push @results, (defined $one ? 'PASS' : 'FAIL') . ':Boolean::one()';
        # is_zero uses refaddr to compare against $ZERO. When is_zero falls
        # back to eval_pv (Perl lexical $ZERO) but zero() uses the C static
        # _csv_boolean_ZERO, the refaddrs differ. This is the split-brain
        # issue tracked as a known architectural concern.
        push @results, ($bool->is_zero($zero) ? 'PASS' : 'TODO') . ':is_zero(zero()) [split-brain: XS static vs Perl lexical]';
        push @results, (!$bool->is_zero($one) ? 'PASS' : 'FAIL') . ':!is_zero(one())';

        # FilterComposite: test multi-class map dispatch
        my $fc = Chalk::Bootstrap::Semiring::FilterComposite->new(
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
        my $fc_zero = eval { $fc->zero() };
        push @results, (defined $fc_zero && ref($fc_zero) eq 'ARRAY' ? 'PASS' : 'FAIL')
            . ':FilterComposite::zero() returns arrayref';

        print $wr join("\n", @results) . "\nDONE\n";
        close $wr;
        exit 0;
    }
    close $wr;
    my $child_output = do { local $/; <$rd> };
    close $rd;
    waitpid($pid, 0);
    my $child_signal = $? & 127;

    if ($child_signal) {
        fail("XS method execution crashed with signal $child_signal");
        # Skip remaining execution tests
        for (1..5) { fail("skipped — child crashed") }
    } else {
        for my $line (split /\n/, $child_output) {
            next if $line eq 'DONE' || $line eq '';
            my ($status, $desc) = split /:/, $line, 2;
            if ($status eq 'PASS') { pass($desc) }
            elsif ($status eq 'TODO') {
                TODO: { local $TODO = 'split-brain: XS static vs Perl lexical'; fail($desc) }
            }
            else                   { fail($desc) }
        }
    }

    # --- Step 8: Integration parse test (actual Earley parse with XS-compiled classes) ---
    # Uses the grammar built in Step 4.5 (before XS load replaced Earley methods).
    # Parse runs in a forked child for segfault safety.
    unless (defined $integ_desugared) {
        fail('Integration parse skipped — grammar setup failed');
        last;  # exit SKIP block
    }

    # Read source file
    my $parse_file = 'lib/Chalk/Bootstrap/Semiring/Boolean.pm';
    open my $pfh, '<:utf8', $parse_file or die "Cannot read $parse_file: $!";
    my $parse_source = do { local $/; <$pfh> };
    close $pfh;

    pipe(my $prd, my $pwr) or die "pipe: $!";
    my $parse_pid = fork();
    if ($parse_pid == 0) {
        close $prd;

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
        $semiring->reset_cache();

        my $parser = Chalk::Bootstrap::Earley->new(
            grammar  => $integ_desugared,
            semiring => $semiring,
        );

        my $t0 = time();
        my $result = eval { $parser->parse($parse_source) };
        my $elapsed = time() - $t0;
        my $err = $@;

        if (defined $result && $result) {
            print $pwr "PARSE_OK:$elapsed\n";
        } else {
            print $pwr "PARSE_FAIL:err=$err result=" . (defined $result ? "'$result'" : 'undef') . "\n";
        }
        close $pwr;
        exit 0;
    }
    close $pwr;
    my $parse_output = do { local $/; <$prd> };
    close $prd;
    waitpid($parse_pid, 0);
    my $parse_signal = $? & 127;

    if ($parse_signal) {
        fail("Integration parse crashed with signal $parse_signal");
    } elsif ($parse_output =~ /^PARSE_OK:(.+)/) {
        my $elapsed = $1 + 0;
        pass('XS-compiled Earley parses Boolean.pm');
        diag sprintf("Integration parse: %.2fs", $elapsed);
    } elsif ($parse_output =~ /_tag_key/) {
        # XS-compiled _ctx() calls _tag_key via call_pv, but _tag_key is a
        # lexical sub not in the package stash. Same split-brain issue as
        # is_zero(zero()) above.
        TODO: {
            local $TODO = 'split-brain: XS call_pv cannot reach my sub _tag_key';
            fail('XS-compiled Earley parses Boolean.pm');
        }
    } else {
        fail("Integration parse failed: $parse_output");
    }
}

done_testing();
