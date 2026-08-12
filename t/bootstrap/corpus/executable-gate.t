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
    # the whole t/base ring on this same contract; the ones that pass are pinned
    # here too so the product gate names them directly.
    { name => 'tbase/cond.t', path => "$BASE/cond.t" },
    { name => 'tbase/if.t',   path => "$BASE/if.t"   },
    { name => 'tbase/pat.t',  path => "$BASE/pat.t"  },
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
cmp_ok($passing, '>=', 8,
    'executable-gate floor (8; ALL of them -- `exit N` lowers, which was the last '
  . 'one. A program has no return value: its observable contract is stdout plus '
  . 'exit status, and `exit` is how a perl program sets a nonzero status short of '
  . 'dying. Measured against perl: a trailing expression NEVER reaches the status '
  . '(`perl -e \'my $x = 5; $x\'` exits 0, as does a trailing 0), and a program '
  . 'ends on `leave` with its last statement compiled in VOID context -- there is '
  . 'no implicit exit() of a value. So exit lowers as a TERMINATOR, not a '
  . 'value-producing call: `call void @exit(i32 N)` then `unreachable`, the same '
  . 'shape `die` already used with a hardcoded 255. The unreachable is load-bearing '
  . 'and is pinned by its own case: without it a statement after `exit` still emits '
  . 'and runs, which matches on exit status while printing too much. Bilateral on '
  . 'the status (exit 7 AND exit 0 AND a program with no exit at all) -- a lowering '
  . 'that hardcodes any single constant passes one of those three and fails the '
  . 'others. Prior: the four one-liners plus three STOCK FILES. '
  . 'pat.t joined cond.t and if.t once a match stopped taking its subject from the '
  . 'op\'s pad target unconditionally (perl5-son 12c1ed5): an unbound `/re/` has no '
  . 'target and reads $_, which was being compiled as a read of pad slot 0. '
  . 'cond.t, if.t and pat.t compile AS THEMSELVES -- shebang intact, no '
  . '`sub __main__` wrap, no epilogue strip, exit status compared -- and match perl '
  . 'byte-for-byte. cond.t and if.t had been passing this way for some time before '
  . 'anything asserted it: this gate only ever ran synthetic one-liners, and the '
  . 'worklist that did name real files scored them on a wrapped contract that has '
  . 'since been deleted. Every file-scoring gate now shares one runner. '
  . 'The Int/Str/Bool/Undef return-value type-tag epilogue -- needed only so the '
  . 'corpus harness can read back a fragment\'s return value -- is suppressed at '
  . 'emission time by program_mode => 1 (defaults off; the corpus reads the tag as '
  . 'its oracle). Every program in this gate now passes; ADD programs to raise it '
  . 'further rather than waiting for one to unblock.)');

done_testing();
