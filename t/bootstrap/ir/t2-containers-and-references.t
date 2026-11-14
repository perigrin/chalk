# ABOUTME: Containers and references T2 lowers alone: slices, ranges, \&name, %$r, field
# ABOUTME: defaults, lists chosen by ?: && ||, a sub result dereferenced. Each SAME or refused.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib "lib", "t/lib";

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found (set LLI)" unless -x ( $ENV{LLI} // "/usr/lib/llvm-15/bin/lli" );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => ".pl", UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

# Each line: what T2 does with the program -- `same` (lowered, prints as perl
# does) or `refused` (by name, never a wrong answer).
while ( my $line = <DATA> ) {
    chomp $line;
    my ( $want, $src ) = split /\t/, $line, 2;
    my $r = tap("$src\n");
    if ( $want eq "same" ) { is $r->{verdict}, "SAME", $src or diag $r->{why} // explain $r }
    else { is $r->{verdict}, "REFUSED", "refused: $src" or diag explain $r }
}

done_testing;

__DATA__
same	my @a = (1, 2, 3); my @b = @a[-1, 0, 5]; print scalar(@b), " ", join(",", map { defined $_ ? $_ : "u" } @b), "\n";
same	my %h = (a => 1, b => 2); my @v = @h{qw(b z a)}; print join(",", map { $_ // "u" } @v), "\n";
refused	my @a = (1, 2, 3); my $x = @a[0, 1]; print "$x\n";
same	my @r = (3 .. 1); print scalar(@r), "\n";
same	my $n = 2.7; my @r = (1 .. $n); print "@r\n";
same	my @a = (5, 6, 7); my @s = map { $_ * 2 } @a[1 .. $#a]; print "@s\n";
same	my @a = (5, 6, 7); for my $i (0, 1) { my @s = grep { $_ > 5 } @a[$i .. 2]; print "@s;" } print "\n";
refused	my @a = (1, 2, 3); sub f { $_[0] = 9 } f(@a[0, 1]); print "@a\n";
refused	my @a = (1, 2, 3); for (@a[0, 1]) { $_ = 0 } print "@a\n";
same	my @a = (1, 2, 3); for my $e (@a[0, 1]) { print $e } print "\n";
same	my $r = [1, 2, 3]; my @x = @{$r}[0, 2]; print "@x\n";
refused	my @x = (1 .. 3, 7); print "@x\n";
refused	my $s = join ",", (1 .. 4)[1, 2]; print "$s\n";
refused	my $h = {a => 1}; my %p = %$h; $h->{a} = 2; print $p{a}, $h->{a}, "\n";
same	my $h = {a => 1, b => 2}; my %p = %$h; print join(",", map { "$_=$p{$_}" } sort keys %p), "\n";
same	my $h; my %p = %$h; print scalar(keys %p), "\n";
same	our $g = {x => 5}; print $g->{x}, "\n";
same	my @l = ({i => 2}, {i => 1}); my @s = sort { $a->{i} <=> $b->{i} } @l; print join(",", map { $_->{i} } @s), "\n";
same	my $h = {a => 1}; for my $k (keys $h->%*) { print "$k $h->{$k}\n" }
refused	print exists $ENV{NOPE_X} ? 1 : 0, "\n";
same	sub two { return (1, 2) } my $c = \&two; my @l = $c->(); my $s = $c->(); print scalar(@l), " $s\n";
same	sub add { $_[0] + $_[1] } my $c = \&add; print ref($c), " ", $c->(2, 3), " ", add(4, 5), "\n";
same	use v5.36; sub sg ($x, $y) { $x * $y } my $c = \&sg; print $c->(3, 4), "\n";
same	sub ap { my ($f, @a) = @_; return $f->(@a) } sub inc { $_[0] + 1 } print ap(\&inc, 41), "\n";
refused	my $c = \&nosuch; print defined $c ? 1 : 0, "\n";
same	sub hi { "hi @_" } my %d = (h => \&hi); print $d{h}->("x"), "\n";
same	package P { sub m { "pm" } } my $c = \&P::m; print $c->(), "\n";
same	sub cnt { scalar(@_) } my $c = \&cnt; print $c->(1, 2, 3), "\n";
same	my @a = (1, 2); my $c = 0; my $n = $c ? @a : (); print defined $n ? "d$n" : "u", "\n";
same	my @a = (1, 2); my $c = 1; my $n = $c ? @a : (); print defined $n ? "d$n" : "u", "\n";
same	my $x = [1, 2]; for my $c (0, 1) { my @b = $c ? @$x : (7); print "@b;" } print "\n";
same	my $x = [1, 2]; my $c = 1; my @b = ($c ? @$x : ()); push @b, 3; print "@b @$x\n";
same	sub f { scalar(@_) } my $c = 1; my @a = (1, 2, 3); print f($c ? @a : ()), "\n";
same	my $c = 1; my @a = (1, 2, 3); print join("-", $c ? @a : ("x")), "\n";
same	my %h = (a => 1); my $c = 1; my @l = $c ? %h : (); print "@l\n";
same	my $c = 2; my @l = $c == 1 ? (1) : $c == 2 ? (2, 3) : (); print "@l\n";
same	my $c = 1; my @a = (4, 5); for my $e ($c ? @a : ()) { print $e } print "\n";
same	my $c = 0; my @a = (4, 5); my @m = map { $_ * 2 } ($c ? @a : (9)); print "@m\n";
same	sub f { return $_[0] ? (1, 2) : () } my @x = f(1); my @y = f(0); print scalar(@x), scalar(@y), "\n";
same	use v5.42; use experimental 'class'; class K { field $r = [1]; method add { push @$r, 2; scalar @$r } } my $a = K->new; my $b = K->new; print $a->add, $a->add, $b->add, "\n";
same	use v5.42; use experimental 'class'; class K { field @l = (1, 2); method add { push @l, 3; scalar @l } } my $a = K->new; my $b = K->new; print $a->add, $b->add, $a->add, "\n";
same	use v5.42; use experimental 'class'; class K { field %h = (a => 1); method n { $h{b} = 2; join ",", sort keys %h } } print K->new->n, "\n";
refused	use v5.42; use experimental 'class'; class K { field $x = 3; field $y = $x + 1; method y { $y } } print K->new->y, "\n";
refused	use v5.42; use experimental 'class'; my $n = 5; class K { field $x = $n; method x { $x } } print K->new->x, "\n";
refused	use v5.42; use experimental 'class'; class K { field $r = {a => 1}; method a { $r->{a} } } print K->new->a, "\n";
same	use v5.42; use experimental 'class'; class K { field @l = (1, 2); method s { "@l" } } for (1, 2) { print K->new->s, ";" } print "\n";
same	use v5.42; use experimental 'class'; class K { field @l = (1, 2); method r { @l = (@l, 3); return scalar @l } method s { "@l" } } my $k = K->new; print $k->r, $k->s, "\n";
same	use v5.42; use experimental 'class'; class K { field %h; method set ($r) { %h = %$r; return } method g { join ",", map { "$_$h{$_}" } sort keys %h } } my $k = K->new; $k->set({a => 1, b => 2}); print $k->g, "\n";
refused	use v5.42; use experimental 'class'; class K { field @l = (1); method r { my $n = (@l = (4, 5)); "$n @l" } } print K->new->r, "\n";
same	use v5.42; use experimental 'class'; class K { field %h; method r { %h = (a => 1, b => 2, a => 3); join ",", map { "$_$h{$_}" } sort keys %h } } print K->new->r, "\n";
same	my $r = {a => 1, b => 2}; my $n = %$r; print $n ? "t" : "f", "\n";
same	my $r = {a => 1}; if (%$r) { print "y\n" }
refused	my $r = {a => 1}; my @l = %$r; $r->{b} = 2; print scalar(@l), "\n";
same	my $r = {a => 1}; my %c = (%$r, b => 2); print join(",", sort keys %c), "\n";
same	sub r { [1, 2] } my @a = r()->@*; print "@a\n";
same	sub r { [1, 2] } print scalar(@{ r() }), "\n";
same	sub r { [1, 2] } for my $x (r()->@*) { print $x } print "\n";
same	package O { sub new { bless {l => [3, 4]}, shift } sub l { $_[0]{l} } } my $o = O->new; my @a = $o->l->@*; print "@a\n";
same	sub r { [1, 2] } print r()->[1], "\n";
same	sub r { [1, 2] } my @a = (r()); print scalar(@a), "\n";
same	sub r { (1, 2) } my @a = r(); print "@a\n";
refused	my $c = 1; my @e = (0); if ($c) { @e = (1, 2) } else { @e = (3) } push @e, 9; print "@e\n";
same	my @in = (1, 2); my $c = 0; my @e; if ($c) { @e = @in } else { @e = (5) } print "@e @in\n";
refused	my $r = [1, 2]; my $c = 1; my @e; if ($c) { @e = @$r } else { @e = () } push @e, 3; print "@e|@$r\n";
same	my @e = (1); my $x = \@e; my $c = 1; if ($c) { @e = (2) } print "@$x @e\n";
refused	my @a = (1, 2); my @r = @a && (7, 8); print "@r\n";
refused	my @a; my @r = @a && (7, 8); print "@r|", scalar(@r), "\n";
refused	my @a = (3); my @r = @a || (7, 8); print "@r\n";
refused	my @a; my @r = (@a || (7, 8)); print "@r\n";
same	sub f { 5 } my @r = (f() && "y"); print "@r\n";
same	sub vals { (1, 2, 3) } sub f { my $s = ""; for my $v (vals()) { $s .= $v } $s } print f(), "\n";
same	sub vals { (1, 2, 3) } my $s = ""; for my $v (vals()) { $s .= $v } print "$s\n";
same	sub one { 5 } if (one()) { print "y\n" }
