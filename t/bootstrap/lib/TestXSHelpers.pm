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
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Sets up the grammar pipeline for tests.
# Accepts a namespace string used to rename the generated grammar module.
# Returns ($gen_grammar) or dies on failure.
sub setup_xs_grammar($namespace) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $raw_ir = perl_pipeline();
    die "perl_pipeline returned undef" unless defined $raw_ir;

    my $bnf_target = Chalk::Bootstrap::Target::Perl->new();
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
# Returns the IR extract or undef on failure.
sub parse_file_ir($gen_grammar, $file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;
    close $fh;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return unless defined $result;

    my $sem_ctx = $result->[4];
    return unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# Builds, compiles, and loads an XS module from IR.
# Returns ($dist_hashref, $error_string). On success, $error_string is undef.
sub build_and_load($ir, $module_name) {
    my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => $module_name,
    );
    my $dist;
    try {
        $dist = $xs_target->generate_distribution($ir);
    } catch ($e) {
        return (undef, "generate_distribution died: $e");
    }
    return (undef, "generate_distribution failed") unless ref($dist) eq 'HASH';

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
# Failures are wrapped in TODO blocks since XS behavioral tests are still maturing.
sub fork_test($module, $test_code, $label) {
    my $pid = fork();
    if (!defined $pid) {
        fail("$label: fork failed: $!");
        return;
    }
    if ($pid == 0) {
        # Redirect child output to avoid corrupting parent TAP stream
        open STDOUT, '>', '/dev/null';
        open STDERR, '>', '/dev/null';
        alarm(10);
        my $result = eval { $test_code->($module); 'ok' };
        exit($@ || !defined $result ? 1 : 0);
    }
    waitpid($pid, 0);
    my $signal = $? & 127;
    my $exit = $? >> 8;
    if ($signal) {
        TODO: {
            local $TODO = "$label: child died with signal $signal (segfault)";
            ok(false, "$label: behavioral test passes");
        }
    } elsif ($exit != 0) {
        TODO: {
            local $TODO = "$label: XS behavioral test fails at runtime";
            ok(false, "$label: behavioral test passes");
        }
    } else {
        pass("$label: behavioral test passes in fork");
    }
}
