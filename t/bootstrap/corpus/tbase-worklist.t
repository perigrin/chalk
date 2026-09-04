# ABOUTME: Mode-1 proving ground (I5): drive the I4 runner over the real t/base ring
# ABOUTME: and emit a per-file construct-debt worklist with a monotonic passing-count floor.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

use Chalk::CodeGen::Harness::TbaseWorklist;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';
my $BASE = "$ENV{HOME}/dev/perl5/t/base";

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "perl5 t/base not found at $BASE" unless -d $BASE;

my $W = 'Chalk::CodeGen::Harness::TbaseWorklist';

# The construct-debt worklist: run Mode-1 over the whole t/base ring.
my $report = $W->run;

# --- Acceptance A: no silent drops ------------------------------------------
# Every t/base file is EITHER a PASS or a COUNTED skip that names its first
# unmet blocker. A SKIP with no named blocker is a silent drop and forbidden.
subtest 'every file is PASS or a COUNTED skip with a named first-blocker' => sub {
    for my $file (sort keys $report->{files}->%*) {
        my $e = $report->{files}{$file};
        ok($e->{verdict} eq 'PASS' || $e->{verdict} eq 'SKIP',
            "$file: verdict is PASS or SKIP (got $e->{verdict})");
        if ($e->{verdict} eq 'SKIP') {
            ok(defined $e->{first_blocker} && length $e->{first_blocker},
                "$file: SKIP names its first unmet blocker (no silent drop)");
        }
    }
};

# --- Acceptance B: passed + skipped == total (nothing lost) -----------------
is($report->{passed} + $report->{skipped}, $report->{total},
    'passed + skipped == total files (every file accounted for)');
is(scalar(keys $report->{files}->%*), $report->{total},
    'the worklist has one entry per file');

# --- Acceptance C: monotonic passing-count floor ----------------------------
# The floor locks the stock passing count so it can only go UP as blockers land
# (I7/I8/... un-skip files later). It starts at the CURRENT measured stock pass
# count. Under I1-I6 + I4 that is 0 (the 1 synthetic pass lives in I4's own
# test, not here — this ring is stock files only).
is($W->passing_floor, 3, 'monotonic floor is the current stock pass count (3)');
cmp_ok($report->{passed}, '>=', $W->passing_floor,
    "stock passing count ($report->{passed}) has not regressed below the floor (@{[$W->passing_floor]})");

# --- Acceptance D: a blocker belongs to the ENTRY graph ----------------------
# A file's first_blocker must be the blocker of the program itself, not of some
# other sub the producer happened to GAP first. A reader that takes the first
# GAP in stderr attributes the wrong feature to the file and sends the next
# build at a construct that is not in the way.
#
# rs.t is the case that proves the difference, and WHAT IT PROVES HAS MOVED.
# It was: `main::test_bad_setting` GAPs on an if/else arm and is reported
# BEFORE `main::__PROGRAM__`'s own explicit-filehandle GAP. The producer now
# emits NO gap for rs.t at all (measured: zero GAP lines), so the file reaches
# chalk's backend intact and stops at the first thing THAT cannot lower --
# `op=Call`, from the top-level `ok(...)` calls, which is still
# main::__PROGRAM__'s OWN blocker.
#
# So only the expected string is stale. The negative assertion stays and is
# what carries the test: if attribution regressed to "first blocker anywhere",
# a sub's blocker would surface here instead.
subtest 'a first_blocker is the ENTRY graph blocker, not another sub\'s' => sub {
    my $rs = $report->{files}{'rs.t'} or return fail('rs.t missing from the worklist');
    like($rs->{first_blocker}, qr/cannot lower op=Call/,
        'rs.t reports main::__PROGRAM__\'s own blocker (the top-level ok() call)');
    unlike($rs->{first_blocker}, qr/if\/else arm/,
        'rs.t does not report main::test_bad_setting\'s blocker');
};

# --- The construct-debt table (the real signal) -----------------------------
diag('t/base construct-debt worklist:');
for my $file (sort keys $report->{files}->%*) {
    my $e = $report->{files}{$file};
    diag(sprintf('  %-14s %-5s %s',
        $file, $e->{verdict}, $e->{verdict} eq 'PASS' ? '' : $e->{first_blocker}));
}
diag(sprintf('  ---- passed=%d skipped=%d total=%d floor=%d',
    $report->{passed}, $report->{skipped}, $report->{total}, $W->passing_floor));

done_testing;
