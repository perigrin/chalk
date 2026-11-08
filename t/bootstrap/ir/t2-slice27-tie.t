# ABOUTME: T2 slice 27 -- tie: each array or hash points at a metaobject; tie swaps the default
# ABOUTME: for one whose every access is a method call on the tie object (perigrin's framing).
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

for my $case (
    [ q{package TA; sub TIEARRAY { my $c = shift; $TA::n = shift // 3; bless {}, $c } sub FETCH { my ($s, $i) = @_; $main::L .= "F$i"; "e$i" } sub STORE { my ($s, $i, $v) = @_; $main::L .= "S$i=$v"; 1 } sub FETCHSIZE { $main::L .= "Z"; $TA::n } sub PUSH { $main::L .= "P" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } sub POP { $main::L .= "O"; $TA::n = $TA::n - 1; "popped" } sub SHIFT { $main::L .= "H"; $TA::n = $TA::n - 1; "shifted" } sub UNSHIFT { $main::L .= "U" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } package main; my @a; tie @a, "TA"; $a[1] = "x"; my $v = $a[2]; print "$v ", scalar(@a), " $main::L\n";}, 'a tied array element read and store are FETCH and STORE' ],
    [ q{package TA; sub TIEARRAY { my $c = shift; $TA::n = shift // 3; bless {}, $c } sub FETCH { my ($s, $i) = @_; $main::L .= "F$i"; "e$i" } sub STORE { my ($s, $i, $v) = @_; $main::L .= "S$i=$v"; 1 } sub FETCHSIZE { $main::L .= "Z"; $TA::n } sub PUSH { $main::L .= "P" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } sub POP { $main::L .= "O"; $TA::n = $TA::n - 1; "popped" } sub SHIFT { $main::L .= "H"; $TA::n = $TA::n - 1; "shifted" } sub UNSHIFT { $main::L .= "U" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } package main; my @a; tie @a, "TA"; push @a, 7, 8; my $p = pop @a; my $s = shift @a; unshift @a, 1; print "$p $s ", scalar(@a), " $main::L\n";}, 'push, pop, shift and unshift on a tied array' ],
    [ q{package TA; sub TIEARRAY { my $c = shift; $TA::n = shift // 3; bless {}, $c } sub FETCH { my ($s, $i) = @_; $main::L .= "F$i"; "e$i" } sub STORE { my ($s, $i, $v) = @_; $main::L .= "S$i=$v"; 1 } sub FETCHSIZE { $main::L .= "Z"; $TA::n } sub PUSH { $main::L .= "P" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } sub POP { $main::L .= "O"; $TA::n = $TA::n - 1; "popped" } sub SHIFT { $main::L .= "H"; $TA::n = $TA::n - 1; "shifted" } sub UNSHIFT { $main::L .= "U" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } package main; my @a; tie @a, "TA", 2; print join(",", @a), "|"; for my $e (@a) { print "<$e>" } print " $main::L\n";}, 'a tied array read whole' ],
    [ q{package TA; sub TIEARRAY { my $c = shift; $TA::n = shift // 3; bless {}, $c } sub FETCH { my ($s, $i) = @_; $main::L .= "F$i"; "e$i" } sub STORE { my ($s, $i, $v) = @_; $main::L .= "S$i=$v"; 1 } sub FETCHSIZE { $main::L .= "Z"; $TA::n } sub PUSH { $main::L .= "P" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } sub POP { $main::L .= "O"; $TA::n = $TA::n - 1; "popped" } sub SHIFT { $main::L .= "H"; $TA::n = $TA::n - 1; "shifted" } sub UNSHIFT { $main::L .= "U" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } package main; my @a = (1, 2); my $o = tie @a, "TA"; print tied(@a) == $o ? "same" : "other", " ", scalar(@a); untie @a; print " ", defined(tied(@a)) ? "t" : "u", " @a\n";}, 'tied gives the object; untie gives back the array' ],
    [ q{package TH; sub TIEHASH { bless {}, shift } sub FETCH { my ($s, $k) = @_; $main::L .= "F$k"; $s->{$k} } sub STORE { my ($s, $k, $v) = @_; $main::L .= "S$k"; $s->{$k} = $v } sub EXISTS { my ($s, $k) = @_; $main::L .= "E$k"; exists $s->{$k} } sub DELETE { my ($s, $k) = @_; $main::L .= "D$k"; delete $s->{$k} } sub CLEAR { $main::L .= "C"; 1 } sub FIRSTKEY { my $s = shift; $TH::i = 0; TH::nxt($s) } sub NEXTKEY { my $s = shift; TH::nxt($s) } sub nxt { my $s = shift; my $r; while (!defined($r) && $TH::i < 4) { my $k = $TH::i == 0 ? "a" : $TH::i == 1 ? "b" : $TH::i == 2 ? "x" : "y"; $TH::i = $TH::i + 1; $r = $k if exists $s->{$k}; } $r } package main; my %h; tie %h, "TH"; $h{b} = 2; $h{a} = 1; print $h{a}, exists $h{b} ? "y" : "n", exists $h{z} ? "y" : "n"; delete $h{b}; print " ", join(",", keys %h), " $main::L\n";}, 'a tied hash: FETCH, STORE, EXISTS, DELETE, keys' ],
    [ q{package TH; sub TIEHASH { bless {}, shift } sub FETCH { my ($s, $k) = @_; $main::L .= "F$k"; $s->{$k} } sub STORE { my ($s, $k, $v) = @_; $main::L .= "S$k"; $s->{$k} = $v } sub EXISTS { my ($s, $k) = @_; $main::L .= "E$k"; exists $s->{$k} } sub DELETE { my ($s, $k) = @_; $main::L .= "D$k"; delete $s->{$k} } sub CLEAR { $main::L .= "C"; 1 } sub FIRSTKEY { my $s = shift; $TH::i = 0; TH::nxt($s) } sub NEXTKEY { my $s = shift; TH::nxt($s) } sub nxt { my $s = shift; my $r; while (!defined($r) && $TH::i < 4) { my $k = $TH::i == 0 ? "a" : $TH::i == 1 ? "b" : $TH::i == 2 ? "x" : "y"; $TH::i = $TH::i + 1; $r = $k if exists $s->{$k}; } $r } package main; my %h; tie %h, "TH"; $h{x} = 1; $h{y} = 2; print "$main::L "; print join(",", map { "$_=$h{$_}" } keys %h), " ", join(",", values %h), " $main::L\n";}, 'a tied hash read by keys and values' ],
    [ q{package TW; sub TIEHASH { bless {}, shift } sub CLEAR { $main::L .= "C"; 1 } sub STORE { my ($s, $k, $v) = @_; $main::L .= "S$k"; $s->{$k} = $v } sub FETCH { my ($s, $k) = @_; $main::L .= "F$k"; $s->{$k} } package main; my %h; tie %h, "TW"; %h = (x => 1, y => 2); print $h{y}, " $main::L\n";}, 'a tied hash assigned a list: CLEAR, then STORE each pair' ],
    [ q{package TV; sub TIEARRAY { bless {}, shift } sub CLEAR { $main::L .= "C"; 1 } sub EXTEND { my ($s, $n) = @_; $main::L .= "X$n"; 1 } sub STORE { my ($s, $i, $v) = @_; $main::L .= "S$i=$v"; 1 } sub FETCH { my ($s, $i) = @_; $main::L .= "F$i"; "v$i" } sub FETCHSIZE { $main::L .= "Z"; 2 } package main; my @a; tie @a, "TV"; @a = (7, 8); print $a[1], " $main::L\n";}, 'a tied array assigned a list: CLEAR, EXTEND, then STORE each' ],
    [ q{package TH; sub TIEHASH { bless {}, shift } sub STORE { my ($s, $k, $v) = @_; $main::L .= "S$k"; $s->{$k} = $v } sub FETCH { my ($s, $k) = @_; $main::L .= "F$k"; $s->{$k} } package main; my %h; tie %h, "TH"; $h{a} = 1; $h{b} = 2; my $c = shift // 1; my $x = $c && $h{a}; print "$x $main::L\n";}, 'a tied read in an && arm: one FETCH, before the read of what it wrote' ],
    [ q{package TH; sub TIEHASH { bless {}, shift } sub STORE { my ($s, $k, $v) = @_; $main::L .= "S$k"; $s->{$k} = $v } sub FETCH { my ($s, $k) = @_; $main::L .= "F$k"; $s->{$k} } package main; my %h; tie %h, "TH"; $h{a} = 1; $h{b} = 2; my $c = shift // 1; my $x = $c && $h{a} + $h{b}; print "$x $main::L\n";}, 'two tied reads in an && arm' ],
    [ q{package TH; sub TIEHASH { bless {}, shift } sub STORE { my ($s, $k, $v) = @_; $main::L .= "S$k"; $s->{$k} = $v } sub FETCH { my ($s, $k) = @_; $main::L .= "F$k"; $s->{$k} } package main; my %h; tie %h, "TH"; $h{a} = 1; $h{b} = 2; my $c = shift // 0; my $x = $c || $h{b}; $h{a} = 5; print "$x $main::L\n";}, 'a tied read in an || arm, then a store' ],
    [ q{package TH; sub TIEHASH { bless {}, shift } sub STORE { my ($s, $k, $v) = @_; $main::L .= "S$k"; $s->{$k} = $v } sub FETCH { my ($s, $k) = @_; $main::L .= "F$k"; $s->{$k} } package main; my %h; tie %h, "TH"; $h{a} = 1; $h{b} = 2; my $c = shift; my $x = $c // $h{b}; print "$x $main::L\n";}, 'a tied read in a // arm' ],
) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $ll = !$err && $units->[0]{ok} ? $units->[0]{ll} : undef;
    ok(defined $ll && $ll =~ /^; chalk T2/m, "$name: lowered through T2") or diag $err // $units->[0]{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# A REFERENCE TO A TIED AGGREGATE reads it where nothing orders the calls: B::SoN
# refuses it by name.
{
    my ($fh, $pl) = tempfile(SUFFIX => ".pl", UNLINK => 1);
    print $fh q{package TA; sub TIEARRAY { my $c = shift; $TA::n = shift // 3; bless {}, $c } sub FETCH { my ($s, $i) = @_; $main::L .= "F$i"; "e$i" } sub STORE { my ($s, $i, $v) = @_; $main::L .= "S$i=$v"; 1 } sub FETCHSIZE { $main::L .= "Z"; $TA::n } sub PUSH { $main::L .= "P" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } sub POP { $main::L .= "O"; $TA::n = $TA::n - 1; "popped" } sub SHIFT { $main::L .= "H"; $TA::n = $TA::n - 1; "shifted" } sub UNSHIFT { $main::L .= "U" . scalar(@_) . $_[1] . ($_[2] // ""); $TA::n = $TA::n + scalar(@_) - 1; $TA::n } package main; my @a; tie @a, "TA"; my $r = \@a; push @$r, 9; print "$$r[0]\n";};
    close $fh;
    like(scalar qx($^X -I$SON -MO=SoN,json $pl 2>&1 >/dev/null), qr/GAP: a reference to a tied aggregate/, "a tied array through a reference: refused by name");
}

done_testing;
