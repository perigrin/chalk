# ABOUTME: Build XS-compiled Earley parser and use it to parse XS.pm.
# ABOUTME: End-to-end test: IR parse Earley.pm → XS compile → load → parse XS.pm.
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

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load);
use Chalk::Bootstrap::Perl::Target::XS;
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

# === Phase 3: Generate XS distribution ===
$t0 = time();
my $xs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::XSPMParse');
my $dist = eval { $xs->generate_distribution_with_cfg($ir, $sa, $ctx) };
ok(ref($dist) eq 'HASH', 'Phase 3: XS codegen') or BAIL_OUT("XS gen failed: $@");
diag(sprintf "Phase 3: %.1fs", time() - $t0);

# === Phase 4: Build and load XS module ===
$t0 = time();
my $tmpdir = tempdir(CLEANUP => 1);
for my $path (sort keys $dist->%*) {
    my $full_path = "$tmpdir/$path";
    my $dir = dirname($full_path);
    make_path($dir) unless -d $dir;
    open(my $wfh, '>:encoding(UTF-8)', $full_path) or die "Cannot write $full_path: $!";
    print $wfh $dist->{$path};
    close $wfh;
}

my $libs = join(':', 'lib', $ENV{PERL5LIB} // '');
{
    my $output = `cd "$tmpdir" && "$^X" Build.PL 2>&1`;
    my $exit = $? >> 8;
    is($exit, 0, 'Phase 4a: Build.PL') or BAIL_OUT("Build.PL failed: $output");
}
{
    my $output = `cd "$tmpdir" && PERL5LIB="$libs" "$^X" Build 2>&1`;
    my $exit = $? >> 8;
    is($exit, 0, 'Phase 4b: XS compilation') or BAIL_OUT("Build failed: $output");
}

unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
eval { require Test::XSPMParse };
is($@, '', 'Phase 4c: XS module loads') or BAIL_OUT("Load failed: $@");
diag(sprintf "Phase 4: %.1fs", time() - $t0);

# === Phase 5: Create XS parser with Perl grammar + Boolean semiring ===
$t0 = time();
my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
my $xs_parser = eval { Test::XSPMParse->new(
    grammar  => $gen,
    semiring => $bool_sr,
) };
ok(defined $xs_parser, 'Phase 5: XS parser created') or BAIL_OUT("Constructor: $@");
diag(sprintf "Phase 5: %.1fs", time() - $t0);

# === Phase 6: Parse XS.pm with XS-compiled Earley ===
open my $fh, '<:utf8', 'lib/Chalk/Bootstrap/Perl/Target/XS.pm' or die $!;
local $/;
my $xs_source = readline($fh);
close $fh;

my $phase6_start = time();
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
my $elapsed = time() - $phase6_start;

if ($signal) {
    fail("Phase 6: XS parse crashed (signal $signal) after ${elapsed}s");
} elsif ($exit == 124) {
    fail("Phase 6: XS parse timed out (>300s)");
} elsif ($exit == 0) {
    pass("Phase 6: XS.pm parsed with XS Earley (${elapsed}s)");
} else {
    fail("Phase 6: XS parse failed (exit $exit) after ${elapsed}s");
}

done_testing();
