# ABOUTME: `exit N` lowers to the process exit status, not a value.
# ABOUTME: A program's contract is stdout + exit status; exit sets the status.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::ProgramRunner;

# Each probe is a whole PROGRAM, compared against perl on stdout AND exit
# status. `exit` is the only way a perl program sets a nonzero status short of
# dying, and it is the executable gate's one remaining blocker.
my @PROBES = (
    # Bilateral on the STATUS: a lowering that hardcodes `ret i32 0` passes the
    # zero case and fails here, and one that hardcodes any constant fails the
    # other. Both are needed.
    ['exit 7 sets status 7' => <<'SRC', "1\n", 7],
use 5.42.0;
say 1;
exit 7;
SRC
    ['exit 0 sets status 0' => <<'SRC', "1\n", 0],
use 5.42.0;
say 1;
exit 0;
SRC
    # No exit at all must still be 0 -- the partner that catches an `exit`
    # lowering which leaks a status into programs that never call it.
    ['no exit is status 0' => <<'SRC', "1\n", 0],
use 5.42.0;
say 1;
SRC
    # exit ABORTS: the statement after it must not run. Without this, an `exit`
    # lowered as a plain call (no terminator) would print "2" and still exit 7,
    # matching the status while producing wrong stdout.
    ['exit aborts the program' => <<'SRC', "1\n", 7],
use 5.42.0;
say 1;
exit 7;
say 2;
SRC
);

for my $p (@PROBES) {
    my ($name, $src, $want_out, $want_exit) = @$p;
    my ($fh, $path) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $src;
    close $fh;

    my $r = Chalk::CodeGen::Harness::ProgramRunner->run_file($path);

    subtest $name => sub {
        # The perl side is the oracle: assert it matches what this test claims,
        # so a wrong expectation shows up as a broken test rather than a
        # compiler bug.
        is($r->{perl_stdout}, $want_out,  'perl oracle stdout');
        is($r->{perl_exit},   $want_exit, 'perl oracle exit status');

        if (($r->{verdict} // '') eq 'SKIP') {
            fail("chalk could not lower it: " . ($r->{skip_reason} // '?'));
            return;
        }
        is($r->{lli_stdout}, $want_out,  'chalk stdout matches');
        is($r->{lli_exit},   $want_exit, 'chalk exit status matches');
    };
}

done_testing;
