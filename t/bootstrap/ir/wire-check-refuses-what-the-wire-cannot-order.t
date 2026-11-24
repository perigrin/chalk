# ABOUTME: the loader's wire check refuses, by name, the shapes B::SoN's wire gives no order or
# ABOUTME: memory version for (the IR audit's classes W5-W10), and no neighbour of them.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

my $CALL2 = qr/a call used both as a list and as a scalar/;
my $W5    = qr/a captured variable passed to a sub that writes its argument/;
my $DIV   = qr/a (?:division|modulus) whose divisor may be zero, on no control chain/;
my $DEREF = qr/a dereference nothing reads, which may still die/;
my $W8    = qr/a DESTROY method \(\w+::DESTROY\)/;
my $W9    = qr/a read through an element that is not there, which perl makes/;

# Does this B::SoN put a division that may fault on the control chain? (Its
# `placement-pins` does; before it the division floats and is refused here.)
require Chalk::CodeGen::Harness::Producer;
my $PINS_DIV = Chalk::CodeGen::Harness::Producer->pins_divisions;

# Each: [source, the refusal's name (undef: perl's output), what it is].
for my $case (
    # W1 (a package scalar a called sub writes, carried round a loop): B::SoN
    # reads it from memory in the loop now (its `placement`), and the rule
    # that refused it is gone. Perl's answer.
    [ q{our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); } print "$g\n";}, undef, 'W1: a counter a called sub also adds to' ],
    [ q{our $g = 0; sub bump { $g += 10 } for my $i (1..3) { bump(); $g = $g + 1; } print "$g\n";}, undef, 'W1: the call first' ],
    [ q{our $n = 0; sub step { $n++ < 3 } my $t = 0; while (step()) { $t += $n; $n = $n + 0 } print "$t $n\n";}, undef, "W1: the call is the loop's test" ],
    [ q{our $s = ""; sub ap { $s .= $_[0] } for my $c ("a", "b", "c") { $s .= "-"; ap($c) } print "$s\n";}, undef, 'W1: a string appended to' ],
    [ q{our $g = 0; sub show { return "<$_[0]>" } my $o = ""; for my $i (1..3) { $g = $g + 1; $o .= show($i); } print "$g $o\n";},
        undef, 'W1: a sub that does not write the variable' ],
    [ q{our $g = 0; for my $i (1..3) { $g = $g + $i; } print "$g\n";}, undef, 'W1: no call in the loop' ],
    # W4 (ref() and blessed() across a bless): B::SoN gives the read the
    # memory version it reads at and makes the bless the next one, and the
    # rule that refused it is gone. Perl's answer.
    [ q{my $o = {}; my $c = ref($o); bless $o, "K"; my $d = ref($o); print "$c $d\n";}, undef, 'W4: ref either side of a bless' ],
    [ q{use Scalar::Util qw(blessed); my $o = {}; my $a = blessed($o) // "u"; bless $o, "K"; my $b = blessed($o) // "u"; print "$a $b\n";}, undef, 'W4: blessed either side of a bless' ],
    [ q{sub mk { return bless {}, "A" } sub re { bless $_[0], "B"; return } my $o = mk(); my $a = ref($o); re($o); print "$a ", ref($o), "\n";}, undef, 'W4: the bless in a sub' ],
    [ q{package A; sub new { return bless {}, shift } package main; my $o = A->new; print ref($o), "\n";}, undef, 'W4: ref of an object blessed once, fresh' ],
    [ q{use Scalar::Util qw(blessed); my $x = 1; my $r = \$x; print blessed($r) // "u", " ", ref($r), "\n"; bless $r, "S"; print blessed($r), "\n";},
        undef, 'W4: a read printed after the bless' ],
    [ q{use Scalar::Util qw(blessed); my $x = 1; my $r = \$x; my $b = blessed($r) // "u"; my $k = ref($r); bless $r, "S"; print "$b $k ", blessed($r), "\n";},
        undef, 'W4: a read taken before the bless and printed after it' ],
    [ q{package C; sub new { my $c = shift; my $s = {}; bless $s, $c; $s } package main; my $o = C->new; print ref($o), "\n";}, undef, 'W4: ref of what a constructor blessed as a statement' ],
    # W5
    [ q{my $x = 1; my $g = sub { $x }; sub setx { $_[0] = 12 } setx($x); print $g->(), "\n";}, $W5, 'W5: a named sub writes $_[0]' ],
    [ q{my $x = 1; my $g = sub { $x }; my $set = sub { $_[0] = 5 }; $set->($x); print $g->(), "\n";}, $W5, 'W5: a code reference writes $_[0]' ],
    [ q{my $x = 1; my $g = sub { $x }; sub twice { return $_[0] * 2 } print twice($x), $g->(), "\n";}, undef, 'W5: a sub that only reads $_[0]' ],
    # W6 and W7's dies (wire v2 stage 8): the die's way out carries the restores and
    # $@ holds what was thrown, so each of these is perl's output now, refused by nothing.
    # W6
    [ q{our $g = 1; sub t { local $g = 2; die "x\n" } eval { t() }; print "$g\n";}, undef, 'W6: a die out of a sub with a local' ],
    [ q{our $v = 1; sub show { print $v } sub t { local $v = 2; show(); eval { local $v = 3; show(); die "x\n" }; show() } t(); show(); print "\n";},
        undef, 'W6: a local in an eval block that dies' ],
    [ q{our $g = 1; sub t { local $g = 2; return $g + 1 } my $r = eval { t() }; print "$g $r\n";}, undef, 'W6: a local in a sub that cannot die' ],
    # (a call that dies under a live `local`, in a sub with no eval: its way
    # out would need a rethrow that restores first -- the plan's Q9 -- and is
    # refused by name until then)
    [ q{our $g = 1; sub u { die "x\n" } sub t { local $g = 2; u() } eval { t() }; print "$g $@";}, undef, 'W6: a call under a local in a sub with no eval' ],
    [ q{our $g = 1; sub u { 1 } sub t { { local $g = 2; } u() } eval { t() }; print "$g\n";}, undef, 'W6: a call after the local is put back' ],
    # A FAULT OF THE SUB'S OWN under a `local` leaves by no way on the wire
    # either (re-audit 2026-11-23, class B): the rule asked sub calls only, so
    # `sub f { local $g=2; my $z=shift; 1/$z } eval { f(0) }` left $g 2.
    [ q{our $g = 1; sub f { local $g = 2; my $z = shift; 1/$z } eval { f(0) }; print "$g ", ($@ ? 1 : 0), "\n";}, undef, 'W6: a division under a local in a sub with no eval' ],
    [ q{our $g = 1; sub f { local $g = 2; my $z = shift; 5 % $z } eval { f(0) }; print "$g\n";}, undef, 'W6: a modulus' ],
    [ q{our $g = 1; sub f { local $g = 2; my $r = shift; use strict; $$r } eval { f("str") }; print "$g\n";}, undef, 'W6: a strict dereference' ],
    [ q{our $g = 1; sub f { for my $i (1) { local $g = 2; my $q = 1/$_[0] } } eval { f(0) }; print "$g\n";}, undef, 'W6: the local in a loop' ],
    [ q{our $g = 1; sub f { { local $g = 2; } 1/$_[0] } eval { f(0) }; print "$g\n";}, undef, 'W6: a division after the local is put back' ],
    # (design B1: each of these leaves by a rethrow edge -- Exc, restores,
    # Unwind marked rethrow -- and W6 is gone)
    [ q{our ($g, $h) = (1, 1); sub u { die "u\n" } sub t { local $h = 3; u() } sub f { local $g = 2; t(); 1 } eval { f() }; print "$g $h $@";}, undef, 'W6: locals in two subs a die passes through' ],
    [ q{our @g = (1); sub f { local @g = (2, 3); 1 / $_[0] } eval { f(0) }; print "@g ", ($@ ? 1 : 0), "\n";}, undef, 'W6: a local array' ],
    [ q{our $g = 1; sub f { local $g = 2; my $r = eval { 1 / $_[0] }; 1 / $_[0] } eval { f(0) }; print "$g\n";}, undef, 'W6: an eval in the sub, the die after it' ],
    # (a call at a loop's top, before the pass's local: not live there -- the
    # back edge passes the pass-end restore; probe p/lo22)
    [ q{our $g = 1; sub b { $g++ } for my $i (1..3) { b(); local $g = $g + 10; next if $i == 2; print "$g\n"; } eval { 1 }; print "$g\n";}, undef, 'L7: a call before a loop pass\'s local' ],
    # (B::SoN reads what a `local` is to put back, at the version its store
    # replaces: a store with no such read beside it is a plain one)
    [ q{our $g = 1; eval { $g = 2; die "x\n"; $g = 3 }; print "$g\n";}, undef, 'W6: a plain store in an eval block that dies (ev12)' ],
    [ q{our $g = 1; sub t { eval { $g = 2; die "x\n" }; return } t(); print "$g\n";}, undef, 'W6: a plain store in a dying eval, in a sub' ],
    [ q{our $g = 1; eval { local $g = 2; die "x\n" }; print "$g\n";}, undef, 'W6: a local alone in an eval block that dies' ],
    [ q{our $g = 1; eval { $g = $g + 2; die "x\n" }; print "$g\n";}, undef, 'W6: a store of what was read there: the wire of a local' ],
    [ q{our $g = 1; for my $i (1, 2) { eval { $g = 5; die "x\n" }; print "$g\n" }}, undef, 'W6: a store in a dying eval in a loop' ],
    [ q{use v5.42; no warnings; sub g ($x) { die "bad $x\n" if $x > 1; return $x } sub h ($x) { my $r = "n"; try { g($x); } catch ($e) { chomp $e; $r = "c:$e"; } return $r } $@ = "before"; print h(1), " ", h(2), " [$@]\n";},
        undef, 'W6: a try puts $@ back itself, and its chomp of $e is of a copy' ],
    [ q{use v5.42; no warnings; my %c; $c{a} = 1; sub f { 1 } sub g ($k) { return if $k eq "z"; if (exists $c{$k}) { try { f() } catch ($x) { die "A: $x" } 1 } else { 2 } } print g("a"), g("b"), "[", scalar(g("z")) // "u", "]\n";},
        undef, 'W6: a catch that dies again, with no local' ],
    # W7
    # (a B::SoN that pins a division that may fault gives it its place: perl's answer)
    [ q{my $d = @ARGV; my $q = 1 / $d; print "before\n"; print "$q\n";}, ( $PINS_DIV ? undef : $DIV ), 'W7: a division by zero after a print' ],
    [ q{my $d = @ARGV; my $q = 7 % $d; print "before\n"; print "$q\n";}, ( $PINS_DIV ? undef : $DIV ), 'W7: a modulus by zero after a print' ],
    [ q{my $d = @ARGV + 2; my $q = 7 / $d; print "$q\n";}, undef, 'W7: a division used where it stands' ],
    [ q{my $n = @ARGV + 5; my $q = -$n ** 2 / 3; my $m = $n % 2; print "x\n"; print "$q $m\n";}, undef, 'W7: a constant divisor, coerced' ],
    [ q{use strict; my $r; print "a\n"; my @l = @$r; print "b\n";}, $DEREF, 'W7: an unread deref of undef' ],
    [ q{eval { die { code => 7 } }; print ref($@), " ", (ref $@ ? $@->{code} : "str"), "\n";}, undef, 'W7: a die of a hash reference' ],
    [ q{package E; sub new { bless { m => $_[1] }, $_[0] } sub msg { $_[0]{m} } package main; eval { die E->new("oops") }; print ref($@) ? $@->msg : "str:$@", "\n";},
        undef, 'W7: a die of an object' ],
    [ q{eval { die "plain\n" }; print "got $@";}, undef, 'W7: a die of a string' ],
    # W8
    [ q{my @o; sub DESTROY { push @o, "d" } { my $x = bless [], "main"; } print "@o\n";}, $W8, 'W8: DESTROY' ],
    # W9: B::SoN makes the element a read goes through (audit 2026-11-22), so
    # perl's answer, not the refusal (which stays for a wire that does not)
    [ q{my $h = { a => 1 }; my $v = $h->{b}{c}; print exists $h->{b} ? "viv" : "none", "\n";}, undef, 'W9: a nested read of a missing key' ],
    [ q{my $h = { a => { c => 2 } }; my $v = $h->{a}{c}; print "$v\n";}, undef, 'W9: a nested read of a key that is there' ],
    [ q{my $r = {}; $r->{a}{b} = 3; print $r->{a}{b}, "\n";}, undef, 'W9: a nested read of what a store made' ],
    # W10: B::SoN reads a package aggregate flattened into a list at a memory
    # version (wire v2 stage 7), and the rule that refused it is gone.
    [ q{our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";}, undef, 'W10: a package array in a list, then emptied' ],
    [ q{our %g = (a => 1); my @k = (%g); %g = (); print scalar(@k), "\n";}, undef, 'W10: a package hash in a list, then emptied' ],
    [ q{our @g = (1); sub t { local @g = (@g, 2); return scalar @g } print t(), scalar(@g), "\n";}, undef, 'W10: local of itself and more' ],
    [ q{our @g = (1,2); sub f { return (@g, 9) } my @r = f(); @g = (); print "@r\n";}, undef, 'W10: flattened in a sub that writes nothing' ],
    # hash truth: B::SoN reads a hash as a scalar by a Count at a memory
    # version, and the rule that refused the hash itself there is gone.
    [ q{my %h; print "e\n" if !%h; my %g = (a => 1); print "ne\n" if %g;}, undef, 'hash truth: if and !' ],
    [ q{my %h; my $n = %h; print "n=$n\n";}, undef, 'hash truth: my $n = %h' ],
    [ q{my %h; my $a = %h ? 1 : 0; $h{k} = 1; my $b = scalar(%h) ? 1 : 0; print "$a$b\n";}, undef, 'hash truth: ?:' ],
    [ q{my %h = (a => 1, b => 2); my $n = keys %h; print "n=$n\n";}, undef, 'hash truth: keys counted' ],
    [ q{our %g; sub add { $g{$_[0]} = 1 } my $a = %g; add("x"); my $b = %g ? "t" : "f"; print "$a $b ", scalar(%g), "\n";}, undef, 'hash truth: a package hash a called sub fills' ],
    # A list assignment to a hash as a scalar is its right side's count, and
    # B::SoN's wire says so now: a Count of the list assigned, taken before
    # the store. The rule that refused the hash handed to the test is gone.
    # Perl's answer.
    [ q{my $n = (my %h = (a => 1, a => 2)); print "$n ", scalar(keys %h), "\n";}, undef, 'hash assign: counted into a scalar, a duplicate key' ],
    [ q{my %g = (a => 1, b => 2, c => 3); my %h; my $n = (%h = %g); print "$n\n";}, undef, 'hash assign: a hash copied counts keys and values' ],
    [ q{my @l = (a => 1); my %h; if (%h = @l) { print "y $h{a}\n" } else { print "n\n" }}, undef, 'hash assign: an if over a hash assigned an array' ],
    [ q{my @l = (); our %h; print((%h = @l) ? "t" : "f", "\n"); @l = (1, 2, 1, 3); my $n = (%h = @l); print "$n ", scalar(keys %h), "\n";}, undef, 'hash assign: a package hash in a ?:, then counted' ],
    [ q{my @l = (); my %h; print !(%h = @l) ? "empty" : "full", "\n";}, undef, 'hash assign: under a not' ],
    # From a CALL's list it is still refused, by T2 and for its own reason: the
    # call's list is counted and stored, and T2 lowers no hash made of a
    # call's list yet.
    [ q{our %g; sub f { return () } my $n = (%g = f()) ? "t" : "f"; print "$n\n";}, $CALL2, 'hash assign: a package hash assigned a call in a ?:' ],
    [ q{sub f { return (a => 1, a => 2) } my %h; my $n = (%h = f()) ? "t" : "f"; print "$n ", scalar(%h), "\n";}, $CALL2, 'hash assign: a `my` hash assigned a call in a ?:' ],
    [ q{my $n = 0; sub f { return $n++ < 2 ? (a => 1) : () } while (my %i = f()) { print "in\n"; } print "out\n";}, $CALL2, 'hash assign: a while over a `my %i = f()`' ],
) {
    my ( $src, $name, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    if ($name) { is( $v, 'REFUSED', "$what: refused" ) or diag "$v $why"; like( $why, $name, "$what: by name" ) }
    else       { is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why" }
}

# THE RULE IS GONE, not kept beside a wire that no longer needs it: a rule
# nothing can trip is a rule nobody can test.
{
    require Chalk::IR::Serialize::WireCheck;
    ok( !Chalk::IR::Serialize::WireCheck->can('_hash_assigns_read_as_scalars'),
        'hash assign: WireCheck holds no rule for a hash handed to a scalar reader' );
    # (wire v2 stage 8: a die's way out is on the wire, its restores and $@
    # store with it, and $@ holds what was thrown)
    ok( !Chalk::IR::Serialize::WireCheck->can($_), "W6/W7: WireCheck holds no $_" )
        for qw(_locals_a_die_skips _stores_in_a_dying_eval _may_be_a_local _dies_of_references _calls_a_local_dies_through);
}

done_testing;
