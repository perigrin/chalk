# ABOUTME: the loader's wire check refuses, by name, the shapes B::SoN's wire gives no order or
# ABOUTME: memory version for (the IR audit's classes W1, W4-W10, hash truth), and no neighbour of them.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

my $W1    = qr/a package scalar \(\$main::\w+\) carried round a loop as a value/;
my $W4    = qr/ref\(\) or blessed\(\) in a program that blesses a reference it may already have read/;
my $W5    = qr/a captured variable passed to a sub that writes its argument/;
my $W6    = qr/a `local` in a sub a die may leave, under an eval/;
my $W6E   = qr/a store to a package variable \(\$main::v\) in an eval block that dies/;
my $DIV   = qr/a (?:division|modulus) whose divisor may be zero, on no control chain/;
my $DEREF = qr/a dereference nothing reads, which may still die/;
my $DIE   = qr/a die of what may be a reference, where an eval may catch it/;
my $W8    = qr/a DESTROY method \(\w+::DESTROY\)/;
my $W9    = qr/a read through an element that is not there, which perl makes/;
my $W10   = qr/a package array or hash \([\@%]main::\w+\) flattened into a list at no memory version/;
my $HASH  = qr/a hash read as a scalar \(its truth or its count\) at no memory version/;

# Each: [source, the refusal's name (undef: perl's output), what it is].
for my $case (
    # W1
    [ q{our $g = 0; sub bump { $g += 10 } for my $i (1..3) { $g = $g + 1; bump(); } print "$g\n";}, $W1, 'W1: a counter a called sub also adds to' ],
    [ q{our $g = 0; sub bump { $g += 10 } for my $i (1..3) { bump(); $g = $g + 1; } print "$g\n";}, $W1, 'W1: the call first' ],
    [ q{our $n = 0; sub step { $n++ < 3 } my $t = 0; while (step()) { $t += $n; $n = $n + 0 } print "$t $n\n";}, $W1, "W1: the call is the loop's test" ],
    [ q{our $s = ""; sub ap { $s .= $_[0] } for my $c ("a".."c") { $s .= "-"; ap($c) } print "$s\n";}, $W1, 'W1: a string appended to' ],
    [ q{our $g = 0; sub show { return "<$_[0]>" } my $o = ""; for my $i (1..3) { $g = $g + 1; $o .= show($i); } print "$g $o\n";},
        undef, 'W1: a sub that does not write the variable' ],
    [ q{our $g = 0; for my $i (1..3) { $g = $g + $i; } print "$g\n";}, undef, 'W1: no call in the loop' ],
    # W4
    [ q{my $o = {}; my $c = ref($o); bless $o, "K"; my $d = ref($o); print "$c $d\n";}, $W4, 'W4: ref either side of a bless' ],
    [ q{use Scalar::Util qw(blessed); my $o = {}; my $a = blessed($o) // "u"; bless $o, "K"; my $b = blessed($o) // "u"; print "$a $b\n";}, $W4, 'W4: blessed either side of a bless' ],
    [ q{sub mk { return bless {}, "A" } sub re { bless $_[0], "B"; return } my $o = mk(); my $a = ref($o); re($o); print "$a ", ref($o), "\n";}, $W4, 'W4: the bless in a sub' ],
    [ q{package A; sub new { return bless {}, shift } package main; my $o = A->new; print ref($o), "\n";}, undef, 'W4: ref of an object blessed once, fresh' ],
    # W5
    [ q{my $x = 1; my $g = sub { $x }; sub setx { $_[0] = 12 } setx($x); print $g->(), "\n";}, $W5, 'W5: a named sub writes $_[0]' ],
    [ q{my $x = 1; my $g = sub { $x }; my $set = sub { $_[0] = 5 }; $set->($x); print $g->(), "\n";}, $W5, 'W5: a code reference writes $_[0]' ],
    [ q{my $x = 1; my $g = sub { $x }; sub twice { return $_[0] * 2 } print twice($x), $g->(), "\n";}, undef, 'W5: a sub that only reads $_[0]' ],
    # W6
    [ q{our $g = 1; sub t { local $g = 2; die "x\n" } eval { t() }; print "$g\n";}, $W6, 'W6: a die out of a sub with a local' ],
    [ q{our $v = 1; sub show { print $v } sub t { local $v = 2; show(); eval { local $v = 3; show(); die "x\n" }; show() } t(); show(); print "\n";},
        $W6E, 'W6: a local in an eval block that dies' ],
    [ q{our $g = 1; sub t { local $g = 2; return $g + 1 } my $r = eval { t() }; print "$g $r\n";}, undef, 'W6: a local in a sub that cannot die' ],
    [ q{use v5.42; no warnings; sub g ($x) { die "bad $x\n" if $x > 1; return $x } sub h ($x) { my $r = "n"; try { g($x); } catch ($e) { chomp $e; $r = "c:$e"; } return $r } $@ = "before"; print h(1), " ", h(2), " [$@]\n";},
        undef, 'W6: a try puts $@ back itself, and its chomp of $e is of a copy' ],
    [ q{use v5.42; no warnings; my %c; $c{a} = 1; sub f { 1 } sub g ($k) { return if $k eq "z"; if (exists $c{$k}) { try { f() } catch ($x) { die "A: $x" } 1 } else { 2 } } print g("a"), g("b"), "[", scalar(g("z")) // "u", "]\n";},
        undef, 'W6: a catch that dies again, with no local' ],
    # W7
    [ q{my $d = @ARGV; my $q = 1 / $d; print "before\n"; print "$q\n";}, $DIV, 'W7: a division by zero after a print' ],
    [ q{my $d = @ARGV; my $q = 7 % $d; print "before\n"; print "$q\n";}, $DIV, 'W7: a modulus by zero after a print' ],
    [ q{my $d = @ARGV + 2; my $q = 7 / $d; print "$q\n";}, undef, 'W7: a division used where it stands' ],
    [ q{my $n = @ARGV + 5; my $q = -$n ** 2 / 3; my $m = $n % 2; print "x\n"; print "$q $m\n";}, undef, 'W7: a constant divisor, coerced' ],
    [ q{use strict; my $r; print "a\n"; my @l = @$r; print "b\n";}, $DEREF, 'W7: an unread deref of undef' ],
    [ q{eval { die { code => 7 } }; print ref($@), " ", (ref $@ ? $@->{code} : "str"), "\n";}, $DIE, 'W7: a die of a hash reference' ],
    [ q{package E; sub new { bless { m => $_[1] }, $_[0] } sub msg { $_[0]{m} } package main; eval { die E->new("oops") }; print ref($@) ? $@->msg : "str:$@", "\n";},
        $DIE, 'W7: a die of an object' ],
    [ q{eval { die "plain\n" }; print "got $@";}, undef, 'W7: a die of a string' ],
    # W8
    [ q{my @o; sub DESTROY { push @o, "d" } { my $x = bless [], "main"; } print "@o\n";}, $W8, 'W8: DESTROY' ],
    # W9
    [ q{my $h = { a => 1 }; my $v = $h->{b}{c}; print exists $h->{b} ? "viv" : "none", "\n";}, $W9, 'W9: a nested read of a missing key' ],
    [ q{my $h = { a => { c => 2 } }; my $v = $h->{a}{c}; print "$v\n";}, undef, 'W9: a nested read of a key that is there' ],
    # W10
    [ q{our @st = (1); my @c = (@st, 2); @st = (); print "@c\n";}, $W10, 'W10: a package array in a list, then emptied' ],
    [ q{our %g = (a => 1); my @k = (%g); %g = (); print scalar(@k), "\n";}, $W10, 'W10: a package hash in a list, then emptied' ],
    [ q{our @g = (1); sub t { local @g = (@g, 2); return scalar @g } print t(), scalar(@g), "\n";}, $W10, 'W10: local of itself and more' ],
    [ q{our @g = (1,2); sub f { return (@g, 9) } my @r = f(); @g = (); print "@r\n";}, undef, 'W10: flattened in a sub that writes nothing' ],
    # hash truth
    [ q{my %h; print "e\n" if !%h; my %g = (a => 1); print "ne\n" if %g;}, $HASH, 'hash truth: if and !' ],
    [ q{my %h; my $n = %h; print "n=$n\n";}, $HASH, 'hash truth: my $n = %h' ],
    [ q{my %h; my $a = %h ? 1 : 0; $h{k} = 1; my $b = scalar(%h) ? 1 : 0; print "$a$b\n";}, $HASH, 'hash truth: ?:' ],
    [ q{my %h = (a => 1, b => 2); my $n = keys %h; print "n=$n\n";}, undef, 'hash truth: keys counted' ],
) {
    my ( $src, $name, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    if ($name) { is( $v, 'REFUSED', "$what: refused" ) or diag "$v $why"; like( $why, $name, "$what: by name" ) }
    else       { is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why" }
}

done_testing;
