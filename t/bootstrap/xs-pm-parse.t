# ABOUTME: Build XS-compiled Earley parser via Target::C and use it to parse a Perl source file.
# ABOUTME: End-to-end test: IR parse Earley.pm → Target::C compile → load → parse source.
use 5.42.0;
use utf8;

use Test::More;

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
use Chalk::Bootstrap::Semiring::Boolean;

# === Phase 1: Set up grammar pipeline ===
my $t0 = time();
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSPMParse') };
ok(defined $gen, 'Phase 1: grammar pipeline') or BAIL_OUT("Cannot continue: $@");
diag(sprintf "Phase 1: %.1fs", time() - $t0);

# === Phase 2: Parse Earley.pm to IR ===
$t0 = time();
my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm') };
ok(defined $ir, 'Phase 2: Earley.pm → IR') or BAIL_OUT("Parse failed: $@");
diag(sprintf "Phase 2: %.1fs", time() - $t0);

# === Phase 3: Build and load XS module via Target::C ===
$t0 = time();
my ($result, $build_err) = eval { build_and_load($ir, $sa, $ctx, 'Test::XSPMParse') };
ok(defined $result, 'Phase 3: XS module built and loaded') or BAIL_OUT("Build failed: " . ($build_err // $@));
diag(sprintf "Phase 3: %.1fs", time() - $t0);

# === Phase 4: Create XS parser with Perl grammar + Boolean semiring ===
$t0 = time();
my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
my $xs_parser = eval { Test::XSPMParse->new(
    grammar  => $gen,
    semiring => $bool_sr,
) };
ok(defined $xs_parser, 'Phase 4: XS parser created') or BAIL_OUT("Constructor: $@");
diag(sprintf "Phase 4: %.1fs", time() - $t0);

# === Phase 5: Parse with XS-compiled Earley ===
open my $fh, '<:utf8', 'lib/Chalk/Bootstrap/Perl/Target/C.pm' or die $!;
local $/;
my $xs_source = readline($fh);
close $fh;

my $phase5_start = time();
my $pid = fork();
if ($pid == 0) {
    # Child: parse with timeout
    my $child_t0 = time();
    $SIG{ALRM} = sub { print STDERR "TIMEOUT\n"; exit(124); };
    alarm(300);  # 5 minute timeout
    my $result = eval { $xs_parser->parse($xs_source) };
    my $child_elapsed = time() - $child_t0;
    if (defined $result) {
        print STDERR "PASS:${child_elapsed}s\n";
        exit(0);
    } else {
        print STDERR "FAIL:${child_elapsed}s:$@\n";
        exit(1);
    }
}
waitpid($pid, 0);
my $signal = $? & 127;
my $exit = $? >> 8;
my $elapsed = time() - $phase5_start;

if ($signal) {
    fail("Phase 5: XS parse crashed (signal $signal) after ${elapsed}s");
} elsif ($exit == 124) {
    fail("Phase 5: XS parse timed out (>300s)");
} elsif ($exit == 0) {
    pass("Phase 5: source parsed with XS Earley (${elapsed}s)");
} else {
    fail("Phase 5: XS parse failed (exit $exit) after ${elapsed}s");
}

done_testing();
