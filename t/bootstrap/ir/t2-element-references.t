# ABOUTME: references to array elements: \$a[i] is the element itself -- written through
# ABOUTME: either name, kept when the array grows, shifts or is refilled, as perl's.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

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
    [ q{my @a = (1, 2); my $r = \$a[1]; $$r .= "x"; print "@a\n";}, 'an append of a constant through it' ],
    [ q{my @d = (1); my $s = \$d[3]; push @d, 5; $$s = 4; print scalar(@d), " @d[0, 3, 4]\n";}, 'a push, the element not made with the array' ],
    [ q{my @a = (1); my $r = \$a[3]; print scalar(@a), "\n";}, 'taking it makes the element' ],
    [ q{my @a = (10, 20); shift @a; my @r = \(@a); ${$r[0]} = 5; print "@a\n";}, 'a reference to each element, after a shift' ],
    # AT AN INDEX NOT A CONSTANT: B::SoN names the site of one that may die
    # (an index before the start), and perl's message names it.
    [ q{my @e = (1, 2); $e[0] = 0; my $i = 1; $i++ if @ARGV; my $t = \$e[$i]; $$t = 3; print "@e\n";}, 'an index not a constant' ],
    [ q{my @a = (1, 2, 3); my $i = -1; $i-- if @ARGV; my $r = \$a[$i]; $$r = 9; print "@a\n";}, 'an index from the end' ],
    [ q{my @a = (1, 2, 3); for my $i (0 .. 2) { my $r = \$a[$i]; $$r *= 10 } print "@a\n";}, 'an index a loop counts' ],
    [ q{my @a = (1); my $i = 3; $i++ if @ARGV; my $r = \$a[$i]; $$r = 4; print scalar(@a), " $a[3]\n";}, 'an index past the end grows the array' ],
    [ qq{my \@a = (1, 2);\nmy \$i = -5;\n\$i++ if \@ARGV;\nmy \$r = \\\$a[\$i];\nprint "x\\n";\n}, 'an index before the start: perl dies, naming where' ],
    [ qq{my \@a = (1, 2);\nmy \$p = \\\$a[-5];\nprint "x\\n";\n}, 'a constant index before the start: perl dies, naming where' ],
    [ qq{my \@a = (1, 2);\nmy \$i = -9;\n\$i++ if \@ARGV;\neval { my \$q = \\\$a[\$i]; print "no\\n"; 1 } or print "caught: \$@";\nprint "after \@a\\n";\n}, 'its die caught by an eval' ],
    [ q{my $l = [1, 2, 3]; my $i = 2; $i-- if @ARGV; my $r = \$l->[$i]; shift @$l; $$r = 9; print "@$l $$r\n";}, 'through an array reference, an index not a constant' ],
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

# A LITERAL A SUB TAKES A REFERENCE TO, where a store may go through it:
# perl's is read-only. A `local` of a hash element where a reference to one
# is taken: perl's local puts a new element there, which T2's does not. A
# reference to an element of %SIG: its values are a metaobject's. Refused by
# name.
for my $case (
    [ q{sub k { \$_[0] } my $r = k(3); $$r = 4; print "$$r\n";}, 'a literal argument (read-only) stored through', qr/a literal passed where a sub takes a reference/ ],
    [ q{our %h = (a => 1); my $r = \$h{a}; { local $h{a} = 7; print "$h{a} $$r\n"; } print "$h{a} $$r\n";}, 'a local of a hash element', qr/a local of a hash element in a program that takes a reference to one/ ],
    [ q{my $r = \$SIG{__WARN__}; $$r = sub { print "w\n" }; warn "x";}, 'an element of %SIG', qr/a reference to an element of a hash whose values are perl's or a metaobject's/ ],
) {
    my ($src, $name, $re) = @$case;
    my ($ll, undef, $why) = lower($src);
    ok(!defined $ll, "$name: refused");
    like($why // '', qr/T2: out of its slices \(/, "$name: by T2") or diag $why;
    like($why // '', $re, "$name: by name") or diag $why;
}

# A REFERENCE TO AN ELEMENT OF A TIED HASH (perl's is a magic element whose
# reads FETCH): stopped at run time, by name, not the hash's own element.
{
    my ($ll, $pl, $why) = lower(q{package T { sub TIEHASH { bless {}, shift } sub FETCH { 7 } sub STORE {} }
        my %h = (k => 1); tie %h, 'T'; my $r = \$h{k}; print "$$r\n";});
    ok(defined $ll, 'a reference to an element of a tied hash: lowered') or diag $why;
    if (defined $ll) {
        my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $lf $ll; close $lf;
        my $got = run("timeout 20 $LLI $llp");
        like($got->[1], qr/\Achalk: refused at run time: a reference to an element of a tied hash/, 'stopped by name');
        isnt($got->[2], 0, 'not a success');
    }
}

# A REFERENCE TO A HASH ELEMENT is the element's own cell too: the hash made
# one of cells (each value boxed, as an array of aliases is), written through
# either name. Perl's semantics: taking it makes the key; a delete takes the
# element out (the reference keeps it, the hash gets a new one on a store);
# a clear or refill gives the hash new elements; a tie keeps the hash's own,
# and untie puts them back.
for my $case (
    [ q{my %h = (k => 1); my $r = \$h{k}; $$r = 2; print "$h{k}\n";}, 'a store through it' ],
    [ q{my %h = (k => 1); my $r = \$h{k}; $$r++; print "$h{k}\n";}, 'an increment through it' ],
    [ q{my %h = (k => 1); my $r = \$h{k}; my $x = "x"; $$r .= $x; print "$h{k}\n";}, 'an append through it' ],
    [ q{my %h = (k => "v"); my $r = \$h{k}; $$r .= "x"; print "$h{k}\n";}, 'an append of a constant through it' ],
    [ q{my %h = (k => 1); my $r = \$h{k}; $h{k} = 5; print "$$r ", ref($r), "\n";}, 'a store to the hash, read through it' ],
    [ q{my %h; my $r = \$h{x}; print exists $h{x} ? "y" : "n", " ", scalar(keys %h), " ", defined $$r ? "d" : "u", "\n";}, 'taking it makes the key' ],
    [ q{my %h = (k => 1); my $r = \$h{k}; delete $h{k}; $$r = 7; print exists $h{k} ? "y" : "n", " $$r\n"; $h{k} = 3; print "$h{k} $$r\n";}, 'a delete: it keeps the element, the hash gets a new one' ],
    [ q{my %h = (k => 1); my $r = \$h{k}; $$r = 4; my $v = delete $h{k}; print "$v ", scalar(keys %h), "\n";}, 'a delete gives what it held' ],
    [ q{my %h = (k => 1); my $r = \$h{k}; %h = (); $$r = 9; print scalar(keys %h), " $$r\n"; %h = (k => 2); print "$h{k} $$r\n";}, 'a clear and a refill' ],
    [ q{my %h = (k => 1); my $r = \$h{k}; %h = (k => 5); $$r = 9; print "$h{k} $$r\n";}, 'a refill gives new elements' ],
    [ q{my %h = (a => 1, b => 2); my $r = \$h{a}; $$r = 10; print join(",", map { "$_=$h{$_}" } sort keys %h), " ", join(",", sort { $a <=> $b } values %h), "\n"; my %g = %h; $$r = 11; print "$g{a} $h{a}\n";}, 'keys, values and a copy of the hash' ],
    [ q{my %h = (a => 1); my $r = \$h{a}; $$r = 3; my @p = each %h; print "@p\n";}, 'each' ],
    [ q{my %h = (a => 1); my %g = %h; $h{a} = 5; print "$g{a} $h{a}\n";}, 'a copy of a hash the program writes is of its values then' ],
    [ q{sub k { return \$_[0] } my %h = (a => 1); my $r = k($h{a}); $$r = 9; print "$h{a}\n"; delete $h{a}; $$r = 4; print exists $h{a} ? "y" : "n", " $$r\n";}, 'a reference to an argument that is a hash element' ],
    [ q{sub k { return \$_[0] } my %h; my $r = k($h{z}); print exists $h{z} ? "y" : "n", "\n"; $$r = 3; print "$h{z}\n";}, 'a reference to an argument that is a hash element not there makes it' ],
    [ q{my $h = { k => 1 }; my $r = \$h->{k}; $$r = 2; print "$h->{k}\n"; $h->{k} = 6; print "$$r\n";}, 'through a hash reference' ],
    [ q{my %h = (a => 1); my $k = "a"; $k .= "b" if @ARGV; my $r = \$h{$k}; $$r = 3; print "$h{a}\n";}, 'a key not a constant' ],
    [ q{my $x = 1; my %h = (k => \$x); my $r = \$h{k}; print ref($$r), " ${$$r}\n"; ${$h{k}} = 2; print "$x\n";}, 'an element that holds a reference' ],
    [ q{my %h; for my $k (qw(a b a)) { my $r = \$h{$k}; $$r++ } print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";}, 'in a loop' ],
    [ q{my %h = (k => 1); my $e = exists $h{x} ? 1 : 0; my $r = \$h{x}; print "$e ", exists $h{x} ? 1 : 0, "\n";}, 'a read of the hash before it, made before it' ],
    [ q{sub g { my $r = shift; $$r = "s" } my %h = (k => 1); g(\$h{k}); print "$h{k}\n";}, 'passed to a sub that stores through it' ],
    [ q{package T { sub TIEHASH { bless {}, shift } sub FETCH { 7 } sub STORE {} sub EXISTS { 1 } sub DELETE {} sub CLEAR {} sub FIRSTKEY { undef } sub NEXTKEY { undef } }
        my %h = (k => 1); my $r = \$h{k}; print "$$r\n"; tie %h, 'T'; print "$$r $h{k}\n"; untie %h; $$r = 5; print "$h{k}\n";}, 'a hash tied and untied keeps its own elements' ],
) {
    my ($src, $name) = @$case;
    my ($ll, $pl, $why) = lower($src);
    ok(defined $ll, "hash: $name: lowered through T2") or diag $why;
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "hash: $name: perl's output");
    is($got->[1], $want->[1], "hash: $name: perl's message");
    is($got->[2], $want->[2], "hash: $name: perl's exit code");
}

done_testing;
