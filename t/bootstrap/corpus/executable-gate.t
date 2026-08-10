# ABOUTME: The PRODUCT gate: compile a file AS ITSELF and diff stdout + exit status
# ABOUTME: against perl. Measures "does this become a runnable program", not a value.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::CodeGen::Harness::ProgramRunner;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# Chalk is a compiler for generating EXECUTABLES. Every other gate measures
# something adjacent to that:
#   - son-corpus-wide.t asks "does this lowered FRAGMENT produce the right
#     VALUE?" (triple contract over a wrapped sub).
#   - the ring worklist asks "how far into this .t file do we get?"
# Neither asks "does this FILE become a PROGRAM that RUNS?" — so when the
# question came up, a proxy metric filled the vacuum and ranked the work wrong.
#
# This gate asks the product question directly and only:
#     perl  FILE -> (stdout, exit status)
#     chalk FILE -> (stdout, exit status)
#     PASS iff both match EXACTLY.
#
# The comparison itself lives in ProgramRunner, which every file-scoring gate
# shares; see its header for what the contract refuses and why. In short: no
# source-text wrap (the entry point must be FOUND), no epilogue (suppressed at
# emission by program_mode => 1, not stripped afterwards), and exit status is
# part of the contract rather than a health check on the toolchain.
#
# A program that cannot yet compile is reported BLOCKED with a named reason,
# not silently skipped — the number below is an honest roadmap, not a vanity
# metric. Raise the floor as more programs pass.
# ---------------------------------------------------------------------------

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';
my $BASE = $ENV{PERL5_TBASE_DIR} // "$ENV{HOME}/dev/perl5/t/base";

plan skip_all => "perl 5.42 not found at $PERL"      unless -x $PERL;
plan skip_all => "perl5-son not found at $SON"       unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"             unless -x $LLI;
plan skip_all => "perl5 t/base not found at $BASE"   unless -d $BASE;

# Programs whose ENTIRE observable contract is (stdout, exit status). Start
# here: if a hello-world does not round-trip, nothing larger can.
#
# `src` is an inline program written to a tempfile; `path` is a REAL file
# compiled where it lives, byte-for-byte, shebang included. The `path` entries
# are the ones that matter — a synthetic one-liner can be shaped to fit the
# compiler, a stock t/base file cannot.
my @PROGRAMS = (
    { name => 'hello',        src => qq{print "hi\\n";\n} },
    { name => 'two-prints',   src => qq{print "a\\n"; print "b\\n";\n} },
    { name => 'arith-print',  src => qq{my \$x = 2 + 3; print "\$x\\n";\n} },
    { name => 'die-aborts',   src => qq{print "before\\n"; die "boom\\n";\n} },
    { name => 'explicit-exit',src => qq{print "bye\\n"; exit 3;\n} },

    # Stock perl5 t/base files, compiled AS THEMSELVES. tbase-worklist.t scores
    # the whole t/base ring on this same contract; these two are pinned here so
    # the product gate names them directly.
    { name => 'tbase/cond.t', path => "$BASE/cond.t" },
    { name => 'tbase/if.t',   path => "$BASE/if.t"   },
);

my ($passing, @report) = (0);

for my $p (@PROGRAMS) {
    my $path = $p->{path};
    unless (defined $path) {
        (my $fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $p->{src};
        close $fh;
    }

    my $r = Chalk::CodeGen::Harness::ProgramRunner->run_file($path);

    if ($r->{verdict} eq 'SKIP') {
        (my $blocker = $r->{skip_reason} // '(unnamed)') =~ s/\s+\z//;
        push @report, sprintf('  %-14s BLOCKED  %s', $p->{name}, $blocker);
        ok(1, "$p->{name}: blocked, reason named (no silent failure)");
        next;
    }

    $passing++ if $r->{verdict} eq 'PASS';
    push @report, $r->{verdict} eq 'PASS'
        ? sprintf('  %-14s PASS', $p->{name})
        : sprintf('  %-14s DIFF     %s', $p->{name}, $r->{skip_reason});
    ok(1, "$p->{name}: compared against the perl oracle");
}

diag('');
diag('=== EXECUTABLE GATE: does this FILE become a PROGRAM that runs? ===');
diag($_) for @report;
diag(sprintf('  passing: %d/%d', $passing, scalar @PROGRAMS));
diag('');
diag('  A program PASSES only when stdout AND exit status both match perl');
diag('  exactly: no source-text wrap, no epilogue strip, no exit-code');
diag('  tolerance. Raise the floor below as programs start passing.');

# The floor. It starts where the capability actually is, and may only rise.
cmp_ok($passing, '>=', 6,
    'executable-gate floor (6; the four one-liners plus the first two STOCK FILES. '
  . 'cond.t and if.t from perl5 t/base compile AS THEMSELVES -- shebang intact, no '
  . '`sub __main__` wrap, no epilogue strip, exit status compared -- and match perl '
  . 'byte-for-byte. This capability predates the assertion: it went unnoticed because '
  . 'this gate only ever ran synthetic one-liners, and tbase-worklist.t scores the '
  . 'same two files on the WRAPPED contract, where a PASS says nothing about this '
  . 'one. The Int/Str/Bool/Undef return-value type-tag epilogue -- needed only so the '
  . 'corpus harness can read back a fragment\'s return value -- is suppressed at '
  . 'emission time by program_mode => 1 (defaults off; the corpus reads the tag as '
  . 'its oracle). The one remaining one-liner, explicit-exit, is blocked in the '
  . 'backend on an unlowered `exit` Call: "cannot lower op=Call (not in '
  . 'literal-arithmetic slice)". Raise this as more programs pass.)');

done_testing();
