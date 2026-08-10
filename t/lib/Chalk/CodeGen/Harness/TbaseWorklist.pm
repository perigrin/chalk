# ABOUTME: Compiles the real perl5 t/base ring as standalone executables and produces
# ABOUTME: a per-file construct-debt worklist + a monotonic passing floor.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::CodeGen::Harness::ProgramRunner;

# The t/base ring is the proving ground: each stock file is compiled AS ITSELF
# and its stdout + exit status compared against perl (ProgramRunner). This class
# does NOT try to make files pass — it produces the WORKLIST (file ->
# first_blocker) that says WHICH construct to build next, and a monotonic floor
# that locks the stock passing count so it can only rise as blockers land.
#
# The ring was previously scored on the WRAPPED contract, which supplied the
# program an entry point it could not find for itself and discarded its exit
# status. See ProgramRunner's header for why that measured the wrong thing and
# what it cost — a blocker named for one file was a blocker of the wrapper.
class Chalk::CodeGen::Harness::TbaseWorklist {

    # The stock perl5 t/base ring (blead, SHA pinned by HarvestPin). This is the
    # fixed proving-ground corpus; the order is least-to-most complex
    # only for the diag table — verdicts are per-file and order-independent.
    my @FILES = qw(
        num.t translate.t while.t pat.t cond.t if.t lex.t rs.t term.t
    );

    # base_dir() — the perl5 t/base directory the ring is sourced from. Kept as a
    # class method (not a hard-coded literal at the call site) so a test or a
    # future harvest checkout can point it elsewhere via PERL5_TBASE_DIR.
    sub base_dir ($class) {
        $ENV{PERL5_TBASE_DIR} // "$ENV{HOME}/dev/perl5/t/base";
    }

    # files() — the ring's file basenames, in the fixed proving-ground order.
    sub files ($class) { @FILES }

    # passing_floor() — the monotonic passing-count floor: the current stock pass
    # count. Three files (cond.t, if.t, pat.t) compile as standalone executables
    # and match perl on stdout AND exit status, so the floor is 3. It rises as
    # blockers land and files un-skip; the test asserts passed >= floor so a
    # regression (a file that USED to pass now skipping/failing) is LOUD.
    # (Named passing_floor, not floor, to avoid the core `floor` builtin.)
    sub passing_floor ($class) { 3 }

    # run() — compile the whole ring and classify each result into the
    # construct-debt worklist. Returns:
    #   {
    #     files   => { $file => { verdict, first_blocker } },  # per-file worklist
    #     passed  => N,   # stock files that lowered to a behavior-equal PASS
    #     skipped => N,   # counted skips (FAIL is folded in — see below)
    #     total   => N,   # scalar @FILES
    #     histogram => { $reason => $count },   # reason -> count (from ProgramRunner)
    #   }
    #
    # first_blocker for a SKIP is ProgramRunner's real skip_reason (the ENTRY graph's
    # first-unsupported construct) — never a hard-coded guess. A FAIL (a real
    # miscompile) is surfaced with its mismatch reason as its first_blocker AND
    # counted in `skipped` for the passed+skipped==total accounting, so a
    # miscompile can never masquerade as a silent pass.
    sub run ($class) {
        my $base = $class->base_dir;
        my %files;
        my %hist;
        my ($passed, $accounted_non_pass) = (0, 0);

        for my $file (@FILES) {
            my $path   = "$base/$file";
            my $result = Chalk::CodeGen::Harness::ProgramRunner
                ->run_file_into_histogram(\%hist, $path);
            my $verdict = $result->{verdict};

            if ($verdict eq 'PASS') {
                $passed++;
                $files{$file} = { verdict => 'PASS', first_blocker => undef };
            }
            else {
                # SKIP or FAIL: both carry a named reason (skip_reason). A FAIL
                # is a real miscompile — name it as the blocker and count it as a
                # non-pass so accounting stays whole; it must never be silent.
                $accounted_non_pass++;
                $files{$file} = {
                    verdict       => $verdict,
                    first_blocker => $result->{skip_reason}
                        // "unnamed $verdict (should never happen)",
                };
            }
        }

        return {
            files     => \%files,
            passed    => $passed,
            skipped   => $accounted_non_pass,
            total     => scalar @FILES,
            histogram => \%hist,
        };
    }
}
