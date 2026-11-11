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

# THE Test::More IT STANDS IN FOR: `use Test::More 0.88` asks this at compile
# time, where it is answered (the one top-level value that matters).
our $VERSION = '1.302210';

use Exporter 'import';
our @EXPORT = qw(ok is isnt pass fail diag note plan done_testing BAIL_OUT isa_ok can_ok cmp_ok skip is_deeply subtest like unlike);

our $COUNT;     # tests run
our $FAILED;    # of them, failed
our $PLANNED;   # the plan's count, once one is printed
our ( $DIFF_AT, $DIFF_GOT, $DIFF_EXP );   # is_deeply's first difference
our $INDENT;    # four spaces a subtest deep

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
    _err( "#          got: " . _shown($got) . "\n#     expected: " . _shown($expected) . "\n" );
    return 0;
}

# isnt($got, $expected, $name) -- the negation of is.
sub isnt {
    my ( $got, $expected, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    my $same = defined $got ? ( defined $expected && $got eq $expected ) : !defined $expected;
    return 1 if _ok( !$same, $name, $file, $line );
    _err( "#          got: " . _shown($got) . "\n#     expected: anything else\n" );
    return 0;
}

# like($got, qr/.../, $name) and unlike -- a match of the regex (undef read
# as ''), and Test::More's diagnostic. (T2 has no regex engine yet: a program
# calling these is refused there, by name.)
sub like {
    my ( $got, $re, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    my $s = defined $got ? $got : '';
    my $ok = $s =~ $re ? 1 : 0;
    return 1 if _ok( $ok, $name, $file, $line );
    _err( "#                   " . _shown($got) . "\n#     doesn't match '" . $re . "'\n" );
    return 0;
}

sub unlike {
    my ( $got, $re, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    my $s = defined $got ? $got : '';
    my $ok = $s !~ $re ? 1 : 0;
    return 1 if _ok( $ok, $name, $file, $line );
    _err( "#                   " . _shown($got) . "\n#           matches '" . $re . "'\n" );
    return 0;
}

# isa_ok($thing, $class, $name) -- an object or a class by ->isa, a plain
# reference by its type; named as Test::More names each.
sub isa_ok {
    my ( $thing, $class, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    my $what = !defined $thing ? 'undef' : ref $thing ? ( _blessed($thing) ? 'object' : 'reference' ) : 'class';
    my $ok;
    if    ( $what eq 'undef' )     { $ok = 0 }
    elsif ( $what eq 'reference' ) { $ok = ref($thing) eq $class }
    else                           { $ok = $thing->isa($class) }
    my ( $label, $diag );
    if ( defined $name ) {
        $label = "'" . $name . "'";
        $diag  = defined $thing ? $label . " isn't a '" . $class . "'" : $label . " isn't defined";
    }
    elsif ( $what eq 'object' ) {
        $label = "An object of class '" . ref($thing) . "'";
        $diag  = "The object of class '" . ref($thing) . "' isn't a '" . $class . "'";
    }
    elsif ( $what eq 'reference' ) {
        $label = "A reference of type '" . ref($thing) . "'";
        $diag  = "The reference of type '" . ref($thing) . "' isn't a '" . $class . "'";
    }
    elsif ( $what eq 'undef' ) {
        $label = 'undef';
        $diag  = "undef isn't defined";
    }
    else {
        $label = "The class (or class-like) '" . $thing . "'";
        $diag  = $label . " isn't a '" . $class . "'";
    }
    return 1 if _ok( $ok, $label . " isa '" . $class . "'", $file, $line );
    _err( "#     " . $diag . "\n" );
    return 0;
}

# can_ok($class_or_object, @methods) -- each method found by ->can.
sub can_ok {
    my ( $proto, @methods ) = @_;
    my ( undef, $file, $line ) = caller;
    my $class = ref($proto) ? ref($proto) : $proto;
    my $failed = '';
    for my $m (@methods) {
        $failed = $failed . "#     " . $class . "->can('" . $m . "') failed\n" unless $proto->can($m);
    }
    my $label = scalar(@methods) == 1 ? $class . "->can('" . $methods[0] . "')" : $class . "->can(...)";
    return 1 if _ok( $failed eq '', $label, $file, $line );
    _err( $failed );
    return 0;
}

# cmp_ok($got, $op, $expected, $name) -- the comparison named by $op, and
# Test::More's diagnostic for it.
sub cmp_ok {
    my ( $got, $op, $expected, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    my $ok;
    if    ( $op eq '==' ) { $ok = $got == $expected }
    elsif ( $op eq '!=' ) { $ok = $got != $expected }
    elsif ( $op eq '<' )  { $ok = $got < $expected }
    elsif ( $op eq '>' )  { $ok = $got > $expected }
    elsif ( $op eq '<=' ) { $ok = $got <= $expected }
    elsif ( $op eq '>=' ) { $ok = $got >= $expected }
    elsif ( $op eq 'eq' ) { $ok = $got eq $expected }
    elsif ( $op eq 'ne' ) { $ok = $got ne $expected }
    elsif ( $op eq 'lt' ) { $ok = $got lt $expected }
    elsif ( $op eq 'gt' ) { $ok = $got gt $expected }
    elsif ( $op eq 'le' ) { $ok = $got le $expected }
    elsif ( $op eq 'ge' ) { $ok = $got ge $expected }
    else  { die "Test::Chalk: cmp_ok's $op is not supported\n" }
    return 1 if _ok( $ok, $name, $file, $line );
    if ( $op eq '==' || $op eq 'eq' ) {
        _err( "#          got: " . _cmp_shown( $got, $op ) . "\n#     expected: " . _cmp_shown( $expected, $op ) . "\n" );
    }
    elsif ( $op eq '!=' || $op eq 'ne' ) {
        _err( "#          got: " . _cmp_shown( $got, $op ) . "\n#     expected: anything else\n" );
    }
    else {
        _err( "#     " . _shown($got) . "\n#         " . $op . "\n#     " . _shown($expected) . "\n" );
    }
    return 0;
}

# skip($why, $count) -- in a SKIP: block, $count tests passed as skipped, and
# the block left (as Test::More: `last SKIP`, from inside this sub).
sub skip {
    my ( $why, $count ) = @_;
    $count = 1 unless defined $count;
    my $i = 0;
    while ( $i < $count ) {
        $COUNT = $COUNT + 1;
        _out( "ok " . $COUNT . " # skip " . $why . "\n" );
        $i = $i + 1;
    }
    no warnings 'exiting';
    last SKIP;
}

# is_deeply($got, $expected, $name) -- Test::More's _deep_check: two plain
# values as is(); otherwise the structures walked, and where they first
# differ named ($got->{b}[1]).
# shortcut: a hash's keys are walked sorted (perl's own order is its own),
# so with two keys differing Test::More may name the other one first.
sub is_deeply {
    my ( $got, $expected, $name ) = @_;
    my ( undef, $file, $line ) = caller;
    if ( !ref($got) && !ref($expected) ) {
        my $same = defined $got ? ( defined $expected && $got eq $expected ) : !defined $expected;
        return 1 if _ok( $same, $name, $file, $line );
        _err( "#          got: " . _shown($got) . "\n#     expected: " . _shown($expected) . "\n" );
        return 0;
    }
    my $ok;
    if ( ref($got) && ref($expected) ) {
        $ok = _deep( $got, $expected, 0, 0, '$FOO', 0 );
    }
    else {
        $ok = _differ( '$FOO', $got, $expected, 0, 0 );
    }
    return 1 if _ok( $ok, $name, $file, $line );
    _err( "#     Structures begin differing at:\n"
      . "#     " . _replace( $DIFF_AT, '$FOO', '     $got' ) . " = " . $DIFF_GOT . "\n"
      . "#     " . _replace( $DIFF_AT, '$FOO', '$expected' ) . " = " . $DIFF_EXP . "\n" );
    return 0;
}

# _deep($e1, $e2, $missing1, $missing2, $at, $arrow) -- 1 when the two are
# the same; else 0, with the first difference in $DIFF_*.
sub _deep {
    my ( $e1, $e2, $m1, $m2, $at, $arrow ) = @_;
    my $d1 = $m1 || defined $e1;
    my $d2 = $m2 || defined $e2;
    return _differ( $at, $e1, $e2, $m1, $m2 ) if ( $d1 ? 1 : 0 ) != ( $d2 ? 1 : 0 );
    return 1 unless $d1;
    return _differ( $at, $e1, $e2, $m1, $m2 ) if ( $m1 ? 1 : 0 ) != ( $m2 ? 1 : 0 );
    my $r1 = ref $e1;
    my $r2 = ref $e2;
    return 1 if ( $r1 eq '' ) == ( $r2 eq '' ) && $e1 eq $e2;
    return _differ( $at, $e1, $e2, 0, 0 ) if $r1 eq '' || $r2 eq '' || $r1 ne $r2;
    die "Test::Chalk: is_deeply of an object ($r1) is not supported\n" if _blessed($e1);
    # (EACH READ THROUGH A REFERENCE in a helper of its own: made where it is
    # asked. T2 cannot yet place one whose value feeds a ?: across a call.)
    if ( $r1 eq 'ARRAY' ) {
        my $n1  = _alen($e1);
        my $n2  = _alen($e2);
        my $max = $n1 > $n2 ? $n1 : $n2;
        my $i   = 0;
        my $ok  = 1;
        while ( $ok && $i < $max ) {
            my $x1 = _aget( $e1, $i );   # (past its end: undef, and no element made)
            my $x2 = _aget( $e2, $i );
            my $gone1 = $i < $n1 ? 0 : 1;
            my $gone2 = $i < $n2 ? 0 : 1;
            unless ( !$gone1 && !$gone2 && _equal_plain( $x1, $x2 ) ) {
                $ok = _deep( $x1, $x2, $gone1, $gone2, $at . ( $arrow ? '' : '->' ) . '[' . $i . ']', 1 );
            }
            $i = $i + 1;
        }
        return $ok;
    }
    if ( $r1 eq 'HASH' ) {
        # THE BIGGER HASH'S KEYS (the second's on a tie), as Test::More.
        my $keys = _hkeys($e1);
        my $k2   = _hkeys($e2);
        $keys = $k2 unless _alen($keys) > _alen($k2);
        my $n = _alen($keys);
        my $i  = 0;
        my $ok = 1;
        while ( $ok && $i < $n ) {
            my $k = _aget( $keys, $i );
            my $gone1 = _hhas( $e1, $k ) ? 0 : 1;
            my $gone2 = _hhas( $e2, $k ) ? 0 : 1;
            my $x1 = _hget( $e1, $k );   # (no such key: undef, and none made)
            my $x2 = _hget( $e2, $k );
            unless ( !$gone1 && !$gone2 && _equal_plain( $x1, $x2 ) ) {
                $ok = _deep( $x1, $x2, $gone1, $gone2, $at . ( $arrow ? '' : '->' ) . '{' . $k . '}', 1 );
            }
            $i = $i + 1;
        }
        return $ok;
    }
    if ( $r1 eq 'SCALAR' || $r1 eq 'REF' ) {
        return _deep( _sget($e1), _sget($e2), 0, 0, '${' . $at . '}', $arrow );
    }
    return _differ( $at, $e1, $e2, 0, 0 );
}

sub _alen  { my ($r) = @_; return scalar(@$r) }
sub _aget  { my ( $r, $i ) = @_; return $r->[$i] }
sub _hkeys { my ($r) = @_; return [ sort( keys %$r ) ] }
sub _hhas  { my ( $r, $k ) = @_; return exists $r->{$k} }
sub _hget  { my ( $r, $k ) = @_; return $r->{$k} }
sub _sget  { my ($r) = @_; return $$r }

# _equal_plain($a, $b) -- two plain values equal (Test::More's _equal_nonrefs).
sub _equal_plain {
    my ( $x, $y ) = @_;
    return 0 if ref($x) || ref($y);
    return defined $y && $x eq $y if defined $x;
    return !defined $y;
}

# _differ($at, $e1, $e2, $missing1, $missing2) -- note the first difference.
sub _differ {
    my ( $at, $e1, $e2, $m1, $m2 ) = @_;
    $DIFF_AT  = $at;
    $DIFF_GOT = _deep_shown( $e1, $m1 );
    $DIFF_EXP = _deep_shown( $e2, $m2 );
    return 0;
}

sub _deep_shown {
    my ( $v, $missing ) = @_;
    return 'Does not exist' if $missing;
    return 'undef' unless defined $v;
    return "" . $v if ref $v;
    return "'" . $v . "'";
}

# diag(@msg) to STDERR and note(@msg) to STDOUT, each line "# "-prefixed.
sub diag {
    _err( _comment( join( '', @_ ) ) );
    return 0;
}

sub note {
    _out( _comment( join( '', @_ ) ) );
    return 0;
}

# plan(tests => N) prints the plan first; plan(skip_all => $why) skips them all.
sub plan {
    my ( $kind, $arg ) = @_;
    if ( $kind eq 'skip_all' ) {
        _out( "1..0 # SKIP " . $arg . "\n" );
        exit 0;
    }
    die "Test::Chalk: plan $kind is not supported\n" unless $kind eq 'tests';
    $PLANNED = $arg;
    _out( "1.." . $arg . "\n" );
    return 1;
}

# done_testing() -- the plan, after the tests (unless one came first); on a
# failure, Test::More's END summary, and its exit status (the count failed,
# 254 at most).
sub done_testing {
    my $n = $COUNT + 0;
    _out( "1.." . $n . "\n" ) unless defined $PLANNED;
    # IN A SUBTEST the plan is all: the subtest reports the rest.
    if ( defined $INDENT && length $INDENT ) {
        $PLANNED = $n;
        return 1;
    }
    return 1 unless $FAILED;
    my $tests = $FAILED == 1 ? "test" : "tests";
    _err( "# Looks like you failed " . $FAILED . " " . $tests . " of " . $n . ".\n" );
    exit( $FAILED > 254 ? 254 : $FAILED );
}

# subtest($name, $code) -- the code run as a test of its own, its TAP four
# spaces in, its plan after it; then one test here, passing when it did.
# shortcut: a subtest that runs no test fails without Test::More's
# "No tests run" diagnostic.
sub subtest {
    my ( $name, $code ) = @_;
    my ( undef, $file, $line ) = caller;
    _out( "# Subtest: " . $name . "\n" );
    my $count   = $COUNT;
    my $failed  = $FAILED;
    my $planned = $PLANNED;
    my $indent  = $INDENT;
    $COUNT   = 0;
    $FAILED  = 0;
    $PLANNED = undef;
    $INDENT  = ( defined $indent ? $indent : '' ) . '    ';
    $code->();
    my $n = $COUNT + 0;
    _out( "1.." . $n . "\n" ) unless defined $PLANNED;
    my $bad = $FAILED + 0;
    if ($bad) {
        my $tests = $bad == 1 ? "test" : "tests";
        _err( "# Looks like you failed " . $bad . " " . $tests . " of " . $n . ".\n" );
    }
    $COUNT   = $count;
    $FAILED  = $failed;
    $PLANNED = $planned;
    $INDENT  = $indent;
    return _ok( !$bad && $n > 0, $name, $file, $line );
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
    _out( $out . "\n" );
    return 1 if $test;
    $FAILED = $FAILED + 1;
    # UNDER A HARNESS a newline first (Test2::Formatter::TAP): a "Failed test"
    # line on STDERR after a write to STDOUT -- here, always the "not ok".
    print STDERR "\n" if $ENV{HARNESS_ACTIVE};   # (never indented)
    if ( defined $name ) {
        _err( "#   Failed test '" . $name . "'\n#   at " . $file . " line " . $line . ".\n" );
    }
    else {
        _err( "#   Failed test at " . $file . " line " . $line . ".\n" );
    }
    return 0;
}

# _out($text), _err($text) -- to STDOUT or STDERR, each line a subtest's
# indent in.
sub _out { my ($t) = @_; print _indented($t); return 1 }
sub _err { my ($t) = @_; print STDERR _indented($t); return 1 }

sub _indented {
    my ($t) = @_;
    return $t unless defined $INDENT && length $INDENT;
    return $INDENT . _replace( substr( $t, 0, length($t) - 1 ), "\n", "\n" . $INDENT ) . "\n";
}

# _cmp_shown($v, $op) -- as cmp_ok shows a value: a string op's quoted, a
# number op's bare, undef as undef.
sub _cmp_shown {
    my ( $v, $op ) = @_;
    return 'undef' unless defined $v;
    return "'" . $v . "'" if $op eq 'eq' || $op eq 'ne';
    return $v;
}

# _blessed($ref) -- true for an object: a reference whose ref() is not one of
# perl's own types.
# shortcut: an object blessed into a class named like a type (`bless [], 'HASH'`)
# reads as a plain reference; use Scalar::Util's blessed once T2 provides it.
sub _blessed {
    my ($r) = @_;
    my $t = ref $r;
    return 0 if $t eq 'SCALAR' || $t eq 'ARRAY' || $t eq 'HASH' || $t eq 'CODE' || $t eq 'REF' || $t eq 'GLOB' || $t eq 'LVALUE' || $t eq 'FORMAT' || $t eq 'IO' || $t eq 'VSTRING';
    return 1;
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
