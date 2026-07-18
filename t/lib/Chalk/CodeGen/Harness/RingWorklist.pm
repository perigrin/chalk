# ABOUTME: Mode-1 widening (I9): generalize the I5 t/base worklist to run any NAMED
# ABOUTME: perl5 test ring (dir + framework-free filter) through the I4 runner.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::CodeGen::Harness::Mode1Runner;

# The I5 TbaseWorklist pinned ONE ring (t/base) as the Mode-1 proving ground. I9
# widens that to Perl's own ring order — t/cmd, t/opbasic, cherry-picked t/comp —
# by parameterizing the ring: a directory + a framework-free file filter. Each
# ring runs through the SAME I4 Mode1Runner and gets its OWN monotonic passing
# floor, and the combined cross-ring skip histogram is the next-feature worklist.
#
# Like TbaseWorklist this class does NOT try to make files pass: under the current
# head essentially every file is a LOUD COUNTED skip naming its first unmet
# construct. The job is the WORKLIST + per-ring floors + no-silent-drops.
class Chalk::CodeGen::Harness::RingWorklist {

    # Ring definitions, in Perl's own least-to-most-complex order. Each ring is a
    # subdir of perl5 t/ plus a framework filter:
    #   framework_free — 'all' takes every .t; 'grep' cherry-picks only the files
    #                    that do NOT load a test framework (use Test::More /
    #                    require test.pl). re/run/uni are NOT rings here (no
    #                    runtime module loading, regex parked) — deliberately out.
    my %RING = (
        cmd     => { subdir => 'cmd',     framework_free => 'all'  },
        opbasic => { subdir => 'opbasic', framework_free => 'all'  },
        comp    => { subdir => 'comp',    framework_free => 'grep' },
    );

    # A file is a FRAMEWORK file (excluded from a 'grep' ring) when it loads a
    # test framework at runtime: `use Test::More` / any `use Test::*`, or the
    # perl-core `require './test.pl'` harness. Files that define their OWN
    # is/ok/plan inline load no framework and stay in the ring.
    my $FRAMEWORK_RE = qr/use \s+ Test:: | require \s+ [^\n]*\btest\b/x;

    # root() — the perl5 t/ directory the rings are sourced from. Kept as a class
    # method (not a call-site literal) so a test or a future harvest checkout can
    # point it elsewhere via PERL5_T_DIR.
    sub root ($class) {
        $ENV{PERL5_T_DIR} // "$ENV{HOME}/dev/perl5/t";
    }

    # rings() — the named rings, in fixed proving-ground order.
    sub rings ($class) { qw(cmd opbasic comp) }

    # ring_dir($ring) — the absolute directory for one ring.
    sub ring_dir ($class, $ring) {
        my $def = $RING{$ring} or die "unknown ring '$ring'";
        return $class->root . '/' . $def->{subdir};
    }

    # _is_framework($path) — true when the file loads a test framework.
    sub _is_framework ($class, $path) {
        open my $fh, '<', $path or return false;
        my $src = do { local $/; <$fh> };
        close $fh;
        return $src =~ $FRAMEWORK_RE ? true : false;
    }

    # files($ring) — the ring's .t files (basenames, sorted), after the
    # framework-free filter. For a 'grep' ring, framework files are cherry-picked
    # OUT here (see excluded() for the complementary list).
    sub files ($class, $ring) {
        my $def = $RING{$ring} or die "unknown ring '$ring'";
        my $dir = $class->ring_dir($ring);
        my @all = sort map { s{.*/}{}r } glob("$dir/*.t");
        return @all if $def->{framework_free} eq 'all';
        return grep { !$class->_is_framework("$dir/$_") } @all;
    }

    # excluded($ring) — the ring's framework files that were cherry-picked OUT
    # (absolute paths). For an 'all' ring this is empty. This makes the exclusion
    # first-class and auditable: excluded + ringed == on-disk count, so a
    # framework file can never vanish unaccounted.
    sub excluded ($class, $ring) {
        my $def = $RING{$ring} or die "unknown ring '$ring'";
        return () if $def->{framework_free} eq 'all';
        my $dir = $class->ring_dir($ring);
        return grep { $class->_is_framework($_) } sort glob("$dir/*.t");
    }

    # passing_floor($ring) — the monotonic passing-count floor for one ring: its
    # current stock pass count. Under I1-I6 + I4 no stock file in any of these
    # rings lowers to a PASS, so every floor is 0. It rises deliberately as
    # blockers land and files un-skip; run()'s report asserts passed >= floor so a
    # regression (a file that USED to pass now skipping/failing) is LOUD.
    # (Named passing_floor, not floor, to avoid the core `floor` builtin.)
    sub passing_floor ($class, $ring) {
        die "unknown ring '$ring'" unless $RING{$ring};
        return 0;
    }

    # run($ring) — drive Mode-1 over one whole ring and classify each result into
    # the construct-debt worklist. Returns:
    #   {
    #     ring      => $ring,
    #     files     => { $file => { verdict, first_blocker } },  # per-file worklist
    #     passed    => N,   # stock files that lowered to a behavior-equal PASS
    #     skipped   => N,   # counted skips (a FAIL miscompile is folded in)
    #     total     => N,   # framework-free file count for the ring
    #     floor     => N,   # this ring's monotonic passing floor
    #     histogram => { $reason => $count },   # reason -> count (from Mode1Runner)
    #   }
    #
    # first_blocker for a SKIP is Mode1Runner's real skip_reason (the producer's
    # first-unsupported construct) — never a hard-coded guess. A FAIL (a real
    # miscompile) is surfaced with its mismatch reason as its first_blocker AND
    # counted in `skipped` for the passed+skipped==total accounting, so a
    # miscompile can never masquerade as a silent pass.
    sub run ($class, $ring) {
        my $dir = $class->ring_dir($ring);
        my @files = $class->files($ring);
        my %files;
        my %hist;
        my ($passed, $accounted_non_pass) = (0, 0);

        for my $file (@files) {
            my $path   = "$dir/$file";
            my $result = Chalk::CodeGen::Harness::Mode1Runner
                ->run_file_into_histogram(\%hist, $path);
            my $verdict = $result->{verdict};

            if ($verdict eq 'PASS') {
                $passed++;
                $files{$file} = { verdict => 'PASS', first_blocker => undef };
            }
            else {
                # SKIP or FAIL: both carry a named reason (skip_reason). A FAIL is
                # a real miscompile — name it as the blocker and count it as a
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
            ring      => $ring,
            files     => \%files,
            passed    => $passed,
            skipped   => $accounted_non_pass,
            total     => scalar @files,
            floor     => $class->passing_floor($ring),
            histogram => \%hist,
        };
    }
}
