# ABOUTME: Test::Chalk: the subset of Test::More chalk's tests use, in perl that compiles
# ABOUTME: through B::SoN, T2 and lli, giving the same TAP, diagnostics and exit as Test::More.
package Test::Chalk;

# HOW IT GROWS (docs/memory/plan-test-chalk.md): one function at a time, each
# only once a probe using it gives Test::More's bytes through T2
# (t/bootstrap/ir/test-chalk-gives-test-more-s-tap.t). Plain syntax: chalk's own
# grammar must parse this file later.
#
# WHAT RUNS WHEN. Only this file's SUBS are compiled with a program: its
# top-level statements run at compile time under perl (B::SoN's run), never in
# the compiled program. So no state is set up here -- a counter starts undef,
# which `+ 1` reads as 0 -- and nothing an import does at `use` time (a plan
# given as `use Test::Chalk tests => 3`) happens when the program runs.
#
# shortcut: no END block. Test::More checks the plan and prints "Looks like
# you failed ..." at END; here done_testing does it, so a test with a plan and
# no done_testing gives no summary on failure. Grow it when T2 runs END blocks.

use Exporter 'import';
our @EXPORT = qw(ok is isnt pass fail diag note plan done_testing BAIL_OUT);

our $COUNT;     # tests run
our $FAILED;    # of them, failed
our $PLANNED;   # the plan's count, once one is printed

# ok($test, $name) -- "ok N - name", or "not ok" and where it failed.
sub ok {
    my ( $test, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    return _ok( $test, $name, $file, $line );
}

sub pass {
    my ($name) = @_;
    my ( undef, $file, $line ) = caller;
    return _ok( 1, $name, $file, $line );
}

sub fail {
    my ($name) = @_;
    my ( undef, $file, $line ) = caller;
    return _ok( 0, $name, $file, $line );
}

# is($got, $expected, $name) -- eq, with undef equal only to undef.
sub is {
    my ( $got, $expected, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    my $same = defined $got ? ( defined $expected && $got eq $expected ) : !defined $expected;
    return 1 if _ok( $same, $name, $file, $line );
    print STDERR "#          got: " . _shown($got) . "\n#     expected: " . _shown($expected) . "\n";
    return 0;
}

# isnt($got, $expected, $name) -- the negation of is.
sub isnt {
    my ( $got, $expected, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    my $same = defined $got ? ( defined $expected && $got eq $expected ) : !defined $expected;
    return 1 if _ok( !$same, $name, $file, $line );
    print STDERR "#          got: " . _shown($got) . "\n#     expected: anything else\n";
    return 0;
}

# diag(@msg) to STDERR and note(@msg) to STDOUT, each line "# "-prefixed.
sub diag {
    print STDERR _comment( join( '', @_ ) );
    return 0;
}

sub note {
    print _comment( join( '', @_ ) );
    return 0;
}

# plan(tests => N) prints the plan first; plan(skip_all => $why) skips them all.
sub plan {
    my ( $kind, $arg ) = @_;
    if ( $kind eq 'skip_all' ) {
        print "1..0 # SKIP " . $arg . "\n";
        exit 0;
    }
    die "Test::Chalk: plan $kind is not supported\n" unless $kind eq 'tests';
    $PLANNED = $arg;
    print "1.." . $arg . "\n";
    return 1;
}

# done_testing() -- the plan, after the tests (unless one came first); on a
# failure, Test::More's END summary, and its exit status (the count failed,
# 254 at most).
sub done_testing {
    my $n = $COUNT + 0;
    print "1.." . $n . "\n" unless defined $PLANNED;
    return 1 unless $FAILED;
    my $tests = $FAILED == 1 ? "test" : "tests";
    print STDERR "# Looks like you failed " . $FAILED . " " . $tests . " of " . $n . ".\n";
    exit( $FAILED > 254 ? 254 : $FAILED );
}

# BAIL_OUT($why) -- stop the whole run.
sub BAIL_OUT {
    my ($why) = @_;
    print "Bail out!  " . $why . "\n";
    exit 255;
}

sub _ok {
    my ( $test, $name, $file, $line ) = @_;
    $COUNT = $COUNT + 1;
    my $out = $test ? "ok $COUNT" : "not ok $COUNT";
    # A NAME'S # is escaped, so TAP does not read it as a directive.
    $out = $out . " - " . _replace( $name, '#', '\\#' ) if defined $name;
    print $out . "\n";
    return 1 if $test;
    $FAILED = $FAILED + 1;
    # UNDER A HARNESS a newline first (Test2::Formatter::TAP): a "Failed test"
    # line on STDERR after a write to STDOUT -- here, always the "not ok".
    print STDERR "\n" if $ENV{HARNESS_ACTIVE};
    if ( defined $name ) {
        print STDERR "#   Failed test '" . $name . "'\n#   at " . $file . " line " . $line . ".\n";
    }
    else {
        print STDERR "#   Failed test at " . $file . " line " . $line . ".\n";
    }
    return 0;
}

# _shown($v) -- a value as is() shows it: quoted, or undef.
sub _shown {
    my ($v) = @_;
    return 'undef' unless defined $v;
    return "'" . $v . "'";
}

# _comment($msg) -- each line of it "# "-prefixed; a last newline adds no
# line, and an empty message is one "# " line (as Test::More).
sub _comment {
    my ($msg) = @_;
    my $out   = '';
    my $start = 0;
    my $nl    = index( $msg, "\n", $start );
    while ( $nl >= 0 ) {
        $out   = $out . "# " . substr( $msg, $start, $nl - $start ) . "\n";
        $start = $nl + 1;
        $nl    = index( $msg, "\n", $start );
    }
    $out = $out . "# " . substr( $msg, $start ) . "\n" if $start < length($msg) || length($msg) == 0;
    return $out;
}

# _replace($s, $from, $to) -- every $from in $s made $to.
sub _replace {
    my ( $s, $from, $to ) = @_;
    my $out   = '';
    my $start = 0;
    my $at    = index( $s, $from, $start );
    while ( $at >= 0 ) {
        $out   = $out . substr( $s, $start, $at - $start ) . $to;
        $start = $at + length $from;
        $at    = index( $s, $from, $start );
    }
    return $out . substr( $s, $start );
}

1;
