# ABOUTME: Test::Chalk: the subset of Test::More chalk's tests use, in perl that compiles
# ABOUTME: through B::SoN, T2 and lli, giving the same TAP, diagnostics and exit as Test::More.
package Test::Chalk;

# HOW IT GROWS (docs/memory/plan-test-chalk.md): one function at a time, each
# only once a probe using it gives Test::More's bytes through T2
# (t/bootstrap/ir/test-chalk-gives-test-more-s-tap.t). Plain syntax: chalk's own
# grammar must parse this file later.
#
# PERL FIRST, for what chalk's own tests call that T2 does not compile yet
# (use_ok, require_ok, explain: each a string eval or a module loaded at run
# time): proved against Test::More's bytes under perl, by
# t/bootstrap/test-chalk-under-perl.t, so every test in t/ can use this file.
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
our @EXPORT = qw(ok is isnt pass fail diag note plan done_testing BAIL_OUT isa_ok can_ok cmp_ok skip is_deeply subtest like unlike
  use_ok require_ok explain $TODO ref_ok dies lives);

our $COUNT;     # tests run
our $FAILED;    # of them, failed
our $PLANNED;   # the plan's count, once one is printed
our ( $DIFF_AT, $DIFF_GOT, $DIFF_EXP );   # is_deeply's first difference
our $INDENT;    # four spaces a subtest deep
our $SKIP_ALL;  # why the subtest running said plan skip_all
# $TODO, exported as Test::More exports it, so `local $TODO = 'why'` in a
# TODO: block compiles under strict. As Test::More, it is read as the CALLING
# package's $TODO (a `local` replaces the exported alias): while it is true a
# failure is not counted, and its diagnostics go to STDOUT.
our $TODO;
our $TODO_NOW;   # the last test's TODO reason, for its diagnostics
# A FAILED lives' exception (Test2's pending diagnostic): shown after the
# next test's diagnostics if that test fails, dropped by the next test or
# diag either way.
our $PENDING;
our $HELD;      # the pending one the last test failed with, still to show

# $Test::Builder::Level STARTS AT 1, as Test::More sets it, so a helper's
# `local $Test::Builder::Level = $Test::Builder::Level + 1` makes it 2.
# shortcut: set at compile time under perl; a compiled program starts it
# undef, so there the helper's bump is lost.
$Test::Builder::Level = 1 unless defined $Test::Builder::Level;

# ok($test, $name) -- "ok N - name", or "not ok" and where it failed.
sub ok ($;$) {
    my ( $test, $name ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $r = _ok( $test, $name, $file, $line );
    _held();
    return $r;
}

sub pass (;$) {
    my ($name) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $r = _ok( 1, $name, $file, $line );
    _held();
    return $r;
}

sub fail (;$) {
    my ($name) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $r = _ok( 0, $name, $file, $line );
    _held();
    return $r;
}

# is($got, $expected, $name) -- eq, with undef equal only to undef.
sub is ($$;$) {
    my ( $got, $expected, $name ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $same = defined $got ? ( defined $expected && $got eq $expected ) : !defined $expected;
    return 1 if _ok( $same, $name, $file, $line );
    _fdiag( _comment( "         got: " . _shown($got) . "\n    expected: " . _shown($expected) . "\n" ) );
    return 0;
}

# isnt($got, $expected, $name) -- the negation of is.
sub isnt ($$;$) {
    my ( $got, $expected, $name ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $same = defined $got ? ( defined $expected && $got eq $expected ) : !defined $expected;
    return 1 if _ok( !$same, $name, $file, $line );
    _fdiag( _comment( "         got: " . _shown($got) . "\n    expected: anything else\n" ) );
    return 0;
}

# like($got, qr/.../, $name) and unlike -- a match of the regex (undef read
# as ''), and Test::More's diagnostic. (T2 has no regex engine yet: a program
# calling these is refused there, by name.)
sub like ($$;$) {
    my ( $got, $re, $name ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $s = defined $got ? $got : '';
    my $ok = $s =~ $re ? 1 : 0;
    return 1 if _ok( $ok, $name, $file, $line );
    _fdiag( _comment( "                  " . _shown($got) . "\n    doesn't match '" . $re . "'\n" ) );
    return 0;
}

sub unlike ($$;$) {
    my ( $got, $re, $name ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $s = defined $got ? $got : '';
    my $ok = $s !~ $re ? 1 : 0;
    return 1 if _ok( $ok, $name, $file, $line );
    _fdiag( _comment( "                  " . _shown($got) . "\n          matches '" . $re . "'\n" ) );
    return 0;
}

# isa_ok($thing, $class, $name) -- an object or a class by ->isa, a plain
# reference by its type; named as Test::More names each.
#
# isa_ok($thing, [classes], $name) -- Test2's: the thing an object or a
# class name, each class by ->isa, every one it is not listed. (Test2's
# isa_ok($thing, @classes) is Test::More's when there are two or three
# arguments: the third is a name there.)
sub isa_ok ($$;$) {
    my ( $thing, $class, $name ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    return _isa_ok2( $thing, $class, $name, $file, $line ) if ref($class) eq 'ARRAY';
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
    _fdiag( "#     " . $diag . "\n" );
    return 0;
}

sub _isa_ok2 {
    my ( $thing, $classes, $name, $file, $line ) = @_;
    my $shown = !defined $thing ? '<undef>' : ref $thing ? _render_ref($thing) : "" . $thing;
    $shown = _replace( $shown, "\n", "\\n" );
    $shown = _replace( $shown, '#', '' );
    $shown = _no_address($shown);
    my @classes = @$classes;
    $name = scalar(@classes) == 1 ? $shown . "->isa('" . $classes[0] . "')" : $shown . "->isa(...)" unless $name;
    unless ( defined $thing && ( ref $thing ? _blessed($thing) : length $thing ) ) {
        my $what = !defined $thing ? '<undef>' : ref $thing ? ref $thing : "'" . $thing . "'";
        _ok( 0, $name, $file, $line, 1 );
        _fdiag( "# " . $what . " is neither a blessed reference or a package name.\n" );
        return 0;
    }
    my $bad = '';
    for my $c (@classes) {
        $bad = $bad . "# Failed: " . $shown . "->isa('" . $c . "')\n" unless $thing->isa($c);
    }
    return 1 if _ok( $bad eq '', $name, $file, $line, 1 );
    _fdiag($bad);
    return 0;
}

# ref_ok($thing, $type, $name) -- Test2's: a reference, of $type if one is
# given (what it is underneath, for an object).
sub ref_ok ($;$$) {
    my ( $thing, $want, $name ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $type = _rtype($thing);
    my $why;
    if    ( $type eq '' )                 { $why = "# '" . _render_ref($thing) . "' is not a reference\n" }
    elsif ( $want && $type ne $want )     { $why = "# '" . _render_ref($thing) . "' is not a '" . $want . "' reference\n" }
    return 1 if _ok( !defined $why, $name, $file, $line, 1 );
    _fdiag($why);
    return 0;
}

# dies { ... } -- Test2's: the block's exception, or undef if it did not
# die; $@, $! and $? left as they were.
# shortcut: no warning in void context, nor for an exception that is false.
sub dies (&) {
    my ($code) = @_;
    local ( $@, $!, $? );
    my $ok  = eval { $code->(); 1 };
    my $err = $@;
    return undef if $ok;
    return $err;
}

# lives { ... } -- Test2's: true if the block did not die; else false, its
# exception left in $@ and shown after the next test's diagnostics if that
# test fails.
# shortcut: no warning in void context.
sub lives (&) {
    my ($code) = @_;
    my $err;
    {
        local ( $@, $!, $? );
        my $ok = eval { $code->(); 1 };
        return 1 if $ok;
        $err = $@;
    }
    $PENDING = "Exception: " . $err;
    $@ = $err;
    return 0;
}

# _rtype($thing) -- Test2's rtype: what a reference is underneath ('' for
# no reference; a pattern's REGEXP).
sub _rtype {
    my ($r) = @_;
    return '' unless ref $r;
    my $t = _type($r);
    return 'REGEXP' if $t eq 'Regexp';
    return $t;
}

# _render_ref($thing) -- Test2's render_ref: undef as undef, a plain value as
# itself, a reference as TYPE(0x...) after its class.
# shortcut: an object with overloaded "" or 0+ shows as those make it.
sub _render_ref {
    my ($r) = @_;
    return 'undef' unless defined $r;
    return "" . $r unless ref $r;
    return 'Regexp=REGEXP(0x' . sprintf( '%x', 0 + $r ) . ')' if _rtype($r) eq 'REGEXP';
    return "" . $r;
}

# _no_address($s) -- every (0x...) taken out of it.
sub _no_address {
    my ($s) = @_;
    my $at = index( $s, '(0x' );
    while ( $at >= 0 ) {
        my $end = index( $s, ')', $at );
        last if $end < 0;
        $s  = substr( $s, 0, $at ) . substr( $s, $end + 1 );
        $at = index( $s, '(0x' );
    }
    return $s;
}

# can_ok($class_or_object, @methods) -- each method found by ->can.
sub can_ok ($@) {
    my ( $proto, @methods ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    my $class = ref($proto) ? ref($proto) : $proto;
    my $failed = '';
    for my $m (@methods) {
        $failed = $failed . "#     " . $class . "->can('" . $m . "') failed\n" unless $proto->can($m);
    }
    my $label = scalar(@methods) == 1 ? $class . "->can('" . $methods[0] . "')" : $class . "->can(...)";
    return 1 if _ok( $failed eq '', $label, $file, $line );
    _fdiag( $failed );
    return 0;
}

# cmp_ok($got, $op, $expected, $name) -- the comparison named by $op, and
# Test::More's diagnostic for it.
sub cmp_ok ($$$;$) {
    my ( $got, $op, $expected, $name ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
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
        _fdiag( _comment( "         got: " . _cmp_shown( $got, $op ) . "\n    expected: " . _cmp_shown( $expected, $op ) . "\n" ) );
    }
    elsif ( $op eq '!=' || $op eq 'ne' ) {
        _fdiag( _comment( "         got: " . _cmp_shown( $got, $op ) . "\n    expected: anything else\n" ) );
    }
    else {
        _fdiag( _comment( "    " . _shown($got) . "\n        " . $op . "\n    " . _shown($expected) . "\n" ) );
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
    my ( undef, $file, $line ) = caller( _level() - 1 );
    if ( !ref($got) && !ref($expected) ) {
        my $same = defined $got ? ( defined $expected && $got eq $expected ) : !defined $expected;
        return 1 if _ok( $same, $name, $file, $line );
        _fdiag( _comment( "         got: " . _shown($got) . "\n    expected: " . _shown($expected) . "\n" ) );
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
    # (every line four spaces in, a value's own lines too, as Test::More's)
    my $out = "Structures begin differing at:\n"
      . _replace( $DIFF_AT, '$FOO', '     $got' ) . " = " . $DIFF_GOT . "\n"
      . _replace( $DIFF_AT, '$FOO', '$expected' ) . " = " . $DIFF_EXP;
    _fdiag( _comment( "    " . _replace( $out, "\n", "\n    " ) . "\n" ) );
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
    return _differ( $at, $e1, $e2, 0, 0 ) if $r1 eq '' || $r2 eq '';
    # AN OBJECT is walked as what it is underneath, its class ignored
    # (Test::More's _type); one that is none of those (a `class` object) is
    # an error, as there.
    $r1 = _type($e1);
    $r2 = _type($e2);
    return _differ( $at, $e1, $e2, 0, 0 ) if $r1 ne $r2;
    die "Test::Chalk: is_deeply of an object (" . ref($e1) . ") that is no perl type\n" if $r1 eq '';
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

# _type($ref) -- a plain reference's type; an object's, the first of
# Test::More's types it ->isa (its underlying one, or Regexp), else ''.
sub _type {
    my ($r) = @_;
    return ref $r unless _blessed($r);
    for my $t (qw(Regexp ARRAY HASH REF SCALAR GLOB CODE VSTRING)) {
        return $t if $r->isa($t);
    }
    return '';
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
    $PENDING = undef;
    my ($pack) = caller( _level() - 1 );
    my $t = _comment( join( '', @_ ) );
    if ( _todo_of($pack) ) { _out($t) }   # (in a TODO block, to STDOUT)
    else                   { _err($t) }
    return 0;
}

sub note {
    $PENDING = undef;
    _out( _comment( join( '', @_ ) ) );
    return 0;
}

# plan(tests => N) prints the plan first; plan(skip_all => $why) skips them
# all -- the program's, or IN A SUBTEST that subtest's (as Test::More: a die
# the subtest catches, its reason left in $SKIP_ALL).
sub plan {
    my ( $kind, $arg ) = @_;
    if ( $kind eq 'skip_all' ) {
        _out( "1..0 # SKIP " . $arg . "\n" );
        exit 0 unless defined $INDENT && length $INDENT;
        $SKIP_ALL = $arg;
        die "Test::Chalk: skip_all\n";
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
# The code runs in an eval, as Test::More's: a plan skip_all in it skips the
# subtest ("ok N # skip why": a test it failed before is reported, and
# hidden), and a die in it finishes the subtest and goes on dying.
# shortcut: a subtest that runs no test fails without Test::More's
# "No tests run" diagnostic.
sub subtest {
    my ( $name, $code ) = @_;
    my ( undef, $file, $line ) = caller( _level() - 1 );
    _out( "# Subtest: " . $name . "\n" );
    my $count   = $COUNT;
    my $failed  = $FAILED;
    my $planned = $PLANNED;
    my $indent  = $INDENT;
    $COUNT   = 0;
    $FAILED  = 0;
    $PLANNED = undef;
    $INDENT  = ( defined $indent ? $indent : '' ) . '    ';
    $SKIP_ALL = undef;
    my $ran  = eval { $code->(); 1 };
    my $err  = $@;
    my $skip = $SKIP_ALL;
    $SKIP_ALL = undef;
    my $n = $COUNT + 0;
    if ( !$ran && defined $skip ) {
        my $failed_here = $FAILED + 0;
        if ($failed_here) {
            my $tests = $failed_here == 1 ? "test" : "tests";
            _err( "# Looks like you failed " . $failed_here . " " . $tests . " of " . $n . ".\n" );
        }
        $COUNT   = $count;
        $FAILED  = $failed;
        $PLANNED = $planned;
        $INDENT  = $indent;
        $COUNT   = $COUNT + 1;
        _out( "ok " . $COUNT . " # skip " . $skip . "\n" );
        return 1;
    }
    _out( "1.." . $n . "\n" ) unless defined $PLANNED;
    # A PLAN NOT KEPT fails the subtest, as Test::More's.
    my $extra = defined $PLANNED ? $n - $PLANNED : 0;
    if ( $extra != 0 ) {
        my $s = $PLANNED == 1 ? "" : "s";
        _err( "# Looks like you planned " . $PLANNED . " test" . $s . " but ran " . $n . ".\n" );
    }
    my $bad = $FAILED + 0;
    if ($bad) {
        my $tests = $bad == 1 ? "test" : "tests";
        my $run   = $extra == 0 ? "" : " run";
        _err( "# Looks like you failed " . $bad . " " . $tests . " of " . $n . $run . ".\n" );
    }
    $COUNT   = $count;
    $FAILED  = $failed;
    $PLANNED = $planned;
    $INDENT  = $indent;
    my $r = _ok( !$bad && $n > 0 && $extra == 0, $name, $file, $line );
    _held();
    die $err unless $ran;
    return $r;
}

# use_ok($module, @imports) -- `use $module @imports` at run time, in the
# caller's package, as a test named "use $module;"; on failure, the error.
# (A string eval: under perl only, as Test::More's.)
sub use_ok ($;@) {
    my ( $module, @imports ) = @_;
    my ( $pack, $file, $line ) = caller;
    $file =~ y/\n\r/_/;
    my $import = ( scalar(@imports) == 1 && $imports[0] =~ /^\d+(?:\.\d+)?$/ ) ? $imports[0] : '@{$args[0]}';
    my $code = "package " . $pack . ";\n#line " . $line . " " . $file . "\nuse " . $module . " " . $import . ";\n1;\n";
    my ( $result, $error ) = _eval( $code, \@imports );
    return 1 if _ok( $result, "use " . $module . ";", $file, $line );
    chomp $error;
    _fdiag( _comment( "    Tried to use '" . $module . "'.\n    Error:  " . $error . "\n" ) );
    return 0;
}

# require_ok($module) -- `require $module` at run time (a file, if it is not
# a module name), as a test named "require $module;".
sub require_ok ($) {
    my ($module) = @_;
    my ( $pack, $file, $line ) = caller;
    my $name = $module;
    ( my $bare = $module ) =~ s/\b::\b//g;
    $name = "'" . $module . "'" unless $bare =~ /^[a-zA-Z]\w*$/;
    my ( $result, $error ) = _eval( "package " . $pack . ";\nrequire " . $name . ";\n1;\n" );
    return 1 if _ok( $result, "require " . $name . ";", $file, $line );
    chomp $error;
    _fdiag( _comment( "    Tried to require '" . $name . "'.\n    Error:  " . $error . "\n" ) );
    return 0;
}

# _eval($code, @args) -- the code's value and error, $@ and $! left alone.
sub _eval {
    my ( $code, @args ) = @_;
    local ( $@, $!, $SIG{__DIE__} );
    my $result = eval $code;
    return ( $result, $@ );
}

# explain(@things) -- each reference as Data::Dumper shows it (Indent 1,
# Terse, keys sorted), anything else as itself.
sub explain {
    my @things = @_;
    local ( $@, $! );
    require Data::Dumper;
    return map { ref $_ ? Data::Dumper->new( [$_] )->Indent(1)->Terse(1)->Sortkeys(1)->Dump : $_ } @things;
}

# BAIL_OUT($why) -- stop the whole run.
sub BAIL_OUT {
    my ($why) = @_;
    print "Bail out!  " . $why . "\n";
    exit 255;
}

# (a fifth argument: Test2's tool, whose failure says so as Test2 does)
sub _ok {
    my ( $test, $name, $file, $line, $test2 ) = @_;
    my $pending = $PENDING;
    $PENDING = undef;
    $COUNT = $COUNT + 1;
    my $out = $test ? "ok $COUNT" : "not ok $COUNT";
    # A NAME'S # is escaped, so TAP does not read it as a directive.
    $out = $out . " - " . _replace( $name, '#', '\\#' ) if defined $name;
    my ($pack) = caller( _level() );   # (who called the test function)
    my $todo = _todo_of($pack);
    $TODO_NOW = $todo;
    $out = $out . " # TODO " . $todo if $todo;
    _out( $out . "\n" );
    return 1 if $test;
    $FAILED = $FAILED + 1 unless $todo;
    my $failed = $todo ? "Failed (TODO)" : "Failed";
    # UNDER A HARNESS a newline first (Test2::Formatter::TAP): a "Failed test"
    # line on STDERR after a write to STDOUT -- here, always the "not ok".
    # (In a TODO block, where they go to STDOUT, none.)
    print STDERR "\n" if $ENV{HARNESS_ACTIVE} && !$todo;   # (never indented)
    $HELD = $pending;
    my $in = $test2 ? "# " : "#   ";
    if ( defined $name ) {
        _fdiag_raw( $in . $failed . " test '" . $name . "'\n" . $in . "at " . $file . " line " . $line . ".\n" );
    }
    else {
        _fdiag_raw( $in . $failed . " test at " . $file . " line " . $line . ".\n" );
    }
    return 0;
}

# _out($text), _err($text) -- to STDOUT or STDERR, each line a subtest's
# indent in.
sub _out { my ($t) = @_; print _indented($t); return 1 }
sub _err { my ($t) = @_; print STDERR _indented($t); return 1 }

# _fdiag($text) -- the last test's failure diagnostics: to STDERR, or in a
# TODO block to STDOUT; then a failed lives' exception it was held for.
sub _fdiag {
    my ($t) = @_;
    _fdiag_raw($t);
    return _held();
}

sub _fdiag_raw {
    my ($t) = @_;
    return _out($t) if $TODO_NOW;
    return _err($t);
}

# _held() -- a failed lives' exception the last test failed with, shown.
sub _held {
    return 1 unless defined $HELD;
    my $h = $HELD;
    $HELD = undef;
    return _fdiag_raw( _comment($h) );
}

# _level() -- how far up the stack a test function's caller is: 1, or more
# under a helper that raised $Test::Builder::Level, as Test::More reads it
# (for the line a failure is reported at, and whose $TODO it is in).
sub _level {
    my $level = $Test::Builder::Level;
    return defined $level ? $level : 1;
}

# _todo_of($package) -- that package's $TODO.
sub _todo_of {
    my ($pack) = @_;
    return ${ $pack . '::TODO' };
}

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
