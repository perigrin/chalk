# ABOUTME: Mode-1 proving ground (I5): drives the I4 runner over the real perl5 t/base
# ABOUTME: ring and produces a per-file construct-debt worklist + a monotonic passing floor.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::CodeGen::Harness::Mode1Runner;

# The t/base ring is a proving ground for Mode-1: each stock file's assertion
# prints need MORE than the top-level-literal-print constructs I1-I4 support, so
# under the current head every file is a LOUD COUNTED skip naming its first unmet
# construct. This class does NOT try to make files pass — it produces the WORKLIST
# (file -> first_blocker) that says WHICH construct to build next, and a monotonic
# floor that locks the stock passing count so it can only rise as blockers land.
class Chalk::CodeGen::Harness::TbaseWorklist {

    # The stock perl5 t/base ring (blead, SHA pinned by HarvestPin). This is the
    # fixed proving-ground corpus for Mode-1; the order is least-to-most complex
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
    # count. Under I1-I6 + I4 no stock t/base file lowers to a PASS (each needs a
    # not-yet-landed construct), so the floor is 0. It rises deliberately as
    # blockers land and files un-skip; the test asserts passed >= floor so a
    # regression (a file that USED to pass now skipping/failing) is LOUD.
    # (Named passing_floor, not floor, to avoid the core `floor` builtin.)
    sub passing_floor ($class) { 0 }

    # run() — drive Mode-1 over the whole ring and classify each result into the
    # construct-debt worklist. Returns:
    #   {
    #     files   => { $file => { verdict, first_blocker } },  # per-file worklist
    #     passed  => N,   # stock files that lowered to a behavior-equal PASS
    #     skipped => N,   # counted skips (FAIL is folded in — see below)
    #     total   => N,   # scalar @FILES
    #     histogram => { $reason => $count },   # reason -> count (from Mode1Runner)
    #   }
    #
    # first_blocker for a SKIP is Mode1Runner's real skip_reason (the producer's
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
            my $result = Chalk::CodeGen::Harness::Mode1Runner
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
