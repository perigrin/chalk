# ABOUTME: references to array elements: \$a[i] is the element itself -- written through
# ABOUTME: either name, kept when the array grows, shifts or is refilled, as perl's.
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

# lower($src) -> (the module's text or undef, T2's reason)
sub lower ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $u = $units->[0] // {};
    my $ll = !$err && $u->{ok} && ( $u->{path} // '' ) eq 't2' ? $u->{ll} : undef;
    return ($ll, $pl, $err // $u->{path_why} // $u->{err});
}

for my $case (
    [ q{my @a = (1, 2); $a[1] = 3; my $r = \$a[0]; print $$r, "\n"; $$r = 5; print "@a\n"; $a[0] = 7; print $$r, " ", ref($r), "\n";},
      'a reference to an element: read, stored through both ways' ],
    [ q{my @c = (1, 2); my $p = \$c[0]; @c = (7, 8); print "$$p @c\n";},
      'an array stored whole has new elements' ],
    [ q{my @a = (1, 2, 3); my $r = \$a[0]; push @a, 4 .. 40; $$r = 9; print "$a[0] $$r ", scalar(@a), "\n";},
      'an element the array is made with, kept when it grows' ],
    [ q{my $l = [1, 2]; my $r = \$l->[1]; $$r = 5; print "@$l\n"; $l->[1] = 6; print "$$r\n";},
      'an element through an array reference' ],
    [ q{my @a = (10, 20); my @r = \(@a); ${$r[1]} = 5; print "${$r[0]} @a\n";},
      'a reference to each element' ],
    [ q{my @a = (1, 2, 3); $a[0] = 1; my $r = \$a[2]; my @b = @a; $$r = 9; print "@a|@b\n";},
      'a copy of the array is of the values' ],
    [ q{my @a = qw(a b c d); my $s = ""; for my $x (@a) { $s .= $x; shift @a; $s .= $x . ";" } print "$s|@a\n";},
      'a foreach alias is its element after a shift' ],
    [ q{my $l = [1]; my $s = ""; for my $x (@$l) { push @$l, 2 .. 40 if $x == 1; $s .= "$x," } print "$s\n";},
      'a foreach alias read after its array grows' ],
    [ q{sub g { $_[0] = uc $_[0] } my @a = qw(a b); for my $x (@a) { g($x) } print "@a\n";},
      'a foreach alias passed to a sub that writes it' ],
    [ q{sub g { $_[0] = uc $_[0] } my $l = [qw(a b)]; my $s = ""; for my $x (@$l) { g($x); $s .= $x } print "$s|@$l\n";},
      'a foreach alias through a reference passed to a sub that writes it' ],
    [ q{sub g { $_[0] .= "!"; shift @{$_[1]} } my $l = [qw(a b c)]; my $s = ""; for my $x (@$l) { g($x, $l); $s .= $x } print "$s|@$l\n";},
      'a foreach alias written by a sub that shifts its array' ],
    [ q{package T { sub TIEARRAY { bless [], shift } sub FETCH { 7 } sub FETCHSIZE { 1 } sub STORESIZE {} sub CLEAR {} sub EXTEND {} sub STORE {} }
        my @a = (1, 2); $a[0] = 1; my $r = \$a[0]; print "$$r\n"; tie @a, 'T'; print "$$r $a[0]\n"; untie @a; print "@a\n";},
      'an array tied and untied keeps its own elements' ],
    [ q{sub k { return \$_[0] } my @a = (1, 2, 3); my $r = k($a[1]); $$r = 9; print "@a\n";},
      'a reference to an argument that is an element' ],
    [ q{sub k { \$_[0] } my $r = k(3); print $$r, "\n";},
      'a reference to a literal argument, read' ],
    [ q{sub k { return \$_[0] } my $v = 1; my $r = k($v); $$r = 9; print "$v\n";},
      'a reference to an argument that is a variable' ],
    # B::SoN TAKES ONE WHERE IT STANDS, reading the array at that memory
    # version: the element at its index then, whatever reshapes the array
    # before or after; a store through it is a store the array's reads see.
    [ q{my @a = (1, 2, 3); my $r = \$a[0]; shift @a; $$r = 9; print "@a $$r\n";}, 'a shift after it' ],
    [ q{my @a = (1, 2, 3); shift @a; my $r = \$a[0]; $$r = 9; print "@a $$r\n";}, 'a shift before it' ],
    [ q{my @a = (1, 2, 3); my $r = \$a[0]; shift @a; print "$$r\n";}, 'a shift after it, read' ],
    [ q{my @a = (1, 2, 3); shift @a; my $r = \$a[0]; print "$$r\n";}, 'a shift before it, read' ],
    [ q{my @b = (1, 2, 3); my $q = \$b[1]; unshift @b, 0; $$q = 9; print "@b\n";}, 'an unshift' ],
    [ q{my @c = (1, 2); my $p = \$c[0]; @c = (7, 8); push @c, 9; print "$$p @c\n";}, 'the array stored whole' ],
    [ q{my @a = (1, 2); my $r = \$a[0]; $$r = 5; print "@a\n";}, 'a store through it' ],
    [ q{my @a = (1, 2); my $r = \$a[0]; $$r++; print "@a\n";}, 'an increment through it' ],
    [ q{my @a = (1, 2); my $r = \$a[1]; my $x = "x"; $$r .= $x; print "@a\n";}, 'an append through it' ],
    [ q{my @d = (1); my $s = \$d[3]; push @d, 5; $$s = 4; print scalar(@d), " @d[0, 3, 4]\n";}, 'a push, the element not made with the array' ],
    [ q{my @a = (1); my $r = \$a[3]; print scalar(@a), "\n";}, 'taking it makes the element' ],
    [ q{my @a = (10, 20); shift @a; my @r = \(@a); ${$r[0]} = 5; print "@a\n";}, 'a reference to each element, after a shift' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $pl, $why) = lower($src);
    ok(defined $ll, "$name: lowered through T2") or diag $why;
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# AN INDEX NOT A CONSTANT may be before the start, where perl dies naming
# the site B::SoN does not give the reference: refused by name. (And a literal
# a sub takes a reference to, where a store may go through it: perl's is
# read-only.)
for my $case (
    [ q{sub k { \$_[0] } my $r = k(3); $$r = 4; print "$$r\n";}, 'a literal argument (read-only) stored through' ],
    [ q{my @e = (1, 2); $e[0] = 0; my $i = 1; $i++ if @ARGV; my $t = \$e[$i]; $$t = 3; print "@e\n";}, 'an index not a constant' ],
) {
    my ($src, $name) = @$case;
    my ($ll, undef, $why) = lower($src);
    ok(!defined $ll, "$name: refused");
    like($why // '', qr/T2: out of its slices \(a (?:reference to an element|literal passed where a sub takes a reference)/, "$name: by name") or diag $why;
}

# A REFERENCE TO A HASH ELEMENT is not T2's yet: refused by name.
for my $src (q{my %h = (k => 1); my $r = \$h{k}; $$r = 2; print "$h{k}\n";},
             q{my %h = (k => 1); my $r = \$h{k}; $$r++; print "$h{k}\n";},
             q{my %h = (k => 1); my $r = \$h{k}; my $x = "x"; $$r .= $x; print "$h{k}\n";}) {
    my ($ll, undef, $why) = lower($src);
    ok(!defined $ll, 'a reference to a hash element: refused');
    like($why // '', qr/T2: out of its slices \((?:a reference to a hash element|a scalar deref where a reference T2 does not make)/, 'refused by name') or diag $why;
}

done_testing;
