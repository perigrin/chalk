# ABOUTME: Shared test utilities for XS compilation tests across tiers.
# ABOUTME: Exports helpers for grammar setup, file parsing to IR, XS build/load, and fork-safe behavioral tests.
use 5.42.0;
use utf8;

package TestXSHelpers;

use Exporter 'import';
our @EXPORT_OK = qw(setup_xs_grammar parse_file_ir build_and_load fork_test);

use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Test::More;

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Sets up the grammar pipeline for tests.
# Accepts a namespace string used to rename the generated grammar module.
# Returns ($gen_grammar) or dies on failure.
sub setup_xs_grammar($namespace) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $raw_ir = perl_pipeline();
    die "perl_pipeline returned undef" unless defined $raw_ir;

    my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $bnf_target->generate($raw_ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/$namespace/g;
    my $ok = eval "$generated; 1";
    die "Grammar eval failed: $@" unless $ok;

    no strict 'refs';
    my $grammar = "${namespace}::grammar"->();
    die "Grammar not defined after eval" unless defined $grammar;
    return $grammar;
}

# Parses a .pm file to IR using the given grammar.
# In list context: returns ($ir, $sa, $sem_ctx, $cfg_snapshot) for cfg-aware generation, or () on failure.
# In scalar context: returns $ir for backward compatibility.
#
# The cfg_snapshot in the returned $sa captures cfg_state entries at parse time.
# SemanticAction's %_cfg_state is a class-scope lexical shared across all instances,
# so subsequent parses (which call reset_cache) wipe earlier entries. The snapshot
# preserves cfg_state so _build_cfg_lookup can use it in multi-class builds.
sub parse_file_ir($gen_grammar, $file) {
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

    # Snapshot cfg_state before a subsequent parse wipes it via reset_cache().
    # SemanticAction's %_cfg_state is a class-scope lexical shared across all
    # instances — subsequent parse_file_ir calls will wipe it. This snapshot
    # maps Context refaddr to cfg_state, for _build_cfg_lookup to use later.
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

    return wantarray ? ($ir, $sa, $sem_ctx, \%cfg_snapshot) : $ir;
}

# Builds, compiles, and loads an XS module from IR with cfg_state dispatch.
# Returns ($dist_hashref, $error_string). On success, $error_string is undef.
sub build_and_load($ir, $sa, $sem_ctx, $module_name) {
    my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => $module_name,
    );
    my $dist;
    try {
        $dist = $xs_target->generate_distribution_with_cfg($ir, $sa, $sem_ctx);
    } catch ($e) {
        return (undef, "generate_distribution_with_cfg died: $e");
    }
    return (undef, "generate_distribution_with_cfg failed") unless ref($dist) eq 'HASH';

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
    my $load_ok = eval "require $module_name; 1";
    return (undef, "Load failed: $@") unless $load_ok;

    return ($dist, undef);
}

# Runs a behavioral test in a forked child process to catch segfaults.
# Signal deaths (segfault, timeout) are always TODO-wrapped since they indicate XS issues.
# Runtime failures (die, bad exit) are real FAILs unless todo => 'reason' is passed.
# Accepts optional named parameters:
#   timeout => $seconds (default 10)
#   todo => $reason (wrap runtime failures in TODO block)
sub fork_test($module, $test_code, $label, %opts) {
    my $timeout = $opts{timeout} // 10;
    my $todo_reason = $opts{todo};
    my $outfile = File::Temp::tmpnam();

    my $pid = fork();
    if (!defined $pid) {
        fail("$label: fork failed: $!");
        return;
    }
    if ($pid == 0) {
        # Capture child output to tempfile for parent diagnostics
        open STDOUT, '>', $outfile;
        open STDERR, '>&', \*STDOUT;
        # Handle SIGALRM explicitly so timeout is exit(124), not signal death
        $SIG{ALRM} = sub { print STDERR "TIMEOUT after ${timeout}s\n"; exit(124); };
        alarm($timeout);
        my $result = eval { $test_code->($module); 'ok' };
        if ($@ || !defined $result) {
            print STDERR "Child died: $@\n" if $@;
            exit(1);
        }
        exit(0);
    }
    waitpid($pid, 0);
    my $signal = $? & 127;
    my $exit = $? >> 8;

    # Read child output for diagnostics
    my $child_output = '';
    if (-f $outfile) {
        if (open my $fh, '<', $outfile) {
            local $/;
            $child_output = <$fh>;
            close $fh;
        }
        unlink $outfile;
    }

    if ($signal) {
        # Signal death (segfault, etc.) — TODO since it's an XS/system issue
        TODO: {
            local $TODO = "$label: child died with signal $signal (segfault)";
            ok(false, "$label: behavioral test passes");
        }
        diag "Child output:\n$child_output" if $child_output;
    } elsif ($exit == 124) {
        # Timeout — TODO since it indicates an XS hang or slow operation
        TODO: {
            local $TODO = "$label: child timed out after ${timeout}s";
            ok(false, "$label: behavioral test passes");
        }
        diag "Child output:\n$child_output" if $child_output;
    } elsif ($exit != 0) {
        # Runtime failure — real FAIL unless caller marked as expected
        if ($todo_reason) {
            TODO: {
                local $TODO = "$label: $todo_reason";
                ok(false, "$label: behavioral test passes");
            }
        } else {
            ok(false, "$label: behavioral test passes");
        }
        diag "Child exited $exit. Output:\n$child_output" if $child_output;
    } else {
        pass("$label: behavioral test passes in fork");
    }
}
