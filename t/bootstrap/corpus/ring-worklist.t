# ABOUTME: Mode-1 widening (I9): drive the I4 runner over the perl5 t/cmd, t/opbasic,
# ABOUTME: and cherry-picked framework-free t/comp rings; per-ring worklist + combined histogram.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use Chalk::CodeGen::Harness::RingWorklist;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';
my $ROOT = $ENV{PERL5_T_DIR} // "$ENV{HOME}/dev/perl5/t";

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "perl5 t/ not found at $ROOT"  unless -d $ROOT;

my $C = 'Chalk::CodeGen::Harness::RingWorklist';

# One combined histogram accumulates across every ring: reason -> count. This is
# the next-feature worklist signal (which real Perl feature unlocks the most files).
my %combined_hist;

# The rings, in Perl's own least-to-most-complex ring order: cmd -> opbasic ->
# cherry-picked framework-free comp. Each ring gets its OWN monotonic floor.
for my $ring (qw(cmd opbasic comp)) {
    subtest "ring $ring" => sub {
        my $report = $C->run($ring);

        # --- Acceptance A: no silent drops -------------------------------------
        # Every ring file is EITHER a PASS or a COUNTED skip that names its first
        # unmet blocker. A SKIP with no named blocker is a silent drop, forbidden.
        for my $file (sort keys $report->{files}->%*) {
            my $e = $report->{files}{$file};
            ok($e->{verdict} eq 'PASS' || $e->{verdict} eq 'SKIP',
                "$file: verdict is PASS or SKIP (got $e->{verdict})");
            if ($e->{verdict} eq 'SKIP') {
                ok(defined $e->{first_blocker} && length $e->{first_blocker},
                    "$file: SKIP names its first unmet blocker (no silent drop)");
            }
        }

        # --- Acceptance B: passed + skipped == total (nothing lost) ------------
        is($report->{passed} + $report->{skipped}, $report->{total},
            "$ring: passed + skipped == total files (every file accounted for)");
        is(scalar(keys $report->{files}->%*), $report->{total},
            "$ring: the worklist has one entry per file");

        # --- Acceptance C: per-ring monotonic passing-count floor --------------
        # Each ring's floor locks its stock passing count so it can only rise as
        # blockers land. Under I1-I6 + I4 no stock file lowers to a PASS, so the
        # floor is 0. The test asserts passed >= floor so a regression is LOUD.
        cmp_ok($report->{floor}, '>=', 0, "$ring: floor is a non-negative count");
        cmp_ok($report->{passed}, '>=', $report->{floor},
            "$ring: stock passing count ($report->{passed}) has not regressed below the floor ($report->{floor})");

        # Fold this ring's histogram into the combined cross-ring histogram.
        $combined_hist{$_} += $report->{histogram}{$_}
            for keys $report->{histogram}->%*;

        # --- The per-ring construct-debt table (the real signal) --------------
        diag("ring $ring construct-debt worklist:");
        for my $file (sort keys $report->{files}->%*) {
            my $e = $report->{files}{$file};
            diag(sprintf('  %-22s %-5s %s',
                $file, $e->{verdict},
                $e->{verdict} eq 'PASS' ? '' : $e->{first_blocker}));
        }
        diag(sprintf('  ---- ring=%s passed=%d skipped=%d total=%d floor=%d',
            $ring, $report->{passed}, $report->{skipped},
            $report->{total}, $report->{floor}));
    };
}

# --- Acceptance D: the COMBINED cross-ring histogram is published -------------
# The combined skip histogram (reason -> count across cmd+opbasic+comp) IS the
# next-feature worklist: it ranks which real Perl feature unlocks the most files.
ok(scalar(keys %combined_hist) > 0,
    'combined cross-ring histogram is non-empty (there is a worklist to publish)');
diag('COMBINED cross-ring skip histogram (reason -> count, the next-feature worklist):');
for my $reason (sort { $combined_hist{$b} <=> $combined_hist{$a} or $a cmp $b } keys %combined_hist) {
    diag(sprintf('  %4d  %s', $combined_hist{$reason}, $reason));
}

# --- Acceptance E: framework files are EXCLUDED, not silently failed ----------
# For t/comp, files that load a test framework (use Test::More / require test.pl)
# are cherry-picked OUT of the ring entirely. They are reported as excluded, and
# excluded + total == the on-disk comp file count (nothing vanishes unaccounted).
{
    my $comp = $C->run('comp');
    my @excluded = $C->excluded('comp');
    my $on_disk  = () = glob("$ROOT/comp/*.t");
    cmp_ok(scalar(@excluded), '>', 0,
        'comp: at least one framework file was cherry-picked OUT (excluded)');
    is($comp->{total} + scalar(@excluded), $on_disk,
        "comp: framework-free total + excluded == on-disk comp file count (nothing vanishes)");
    diag(sprintf('comp: %d framework-free files ringed, %d framework files EXCLUDED (of %d on disk)',
        $comp->{total}, scalar(@excluded), $on_disk));
    diag('  excluded (framework): ' . join(', ', map { s{.*/}{}r } @excluded));
}

done_testing;
