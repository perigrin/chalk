# ABOUTME: Library code for the y/yd probes (third final audit, 2026-11-25):
# ABOUTME: a followed module whose file-level code initialises plain package data.
package YInit;
our $n = 1; our $s = "str"; our $f = 1.5; our $e = ""; our $u; our $z = 0;
our $zs = "0.0"; our $one = "1.0"; our $big = 9007199254740993; our $neg = -5;
our $third = 1/3; our $e20 = 1e20; our $nl = "a\nb"; our $qt = q{a"b$c@d\\e};
our $ps = "5"; my $t1 = $ps + 0; our $pn = 5; my $t2 = "$pn"; our $sn = "12abc"; { no warnings; my $t3 = $sn + 0; }
our @l = (1, "a", undef, 2.5); our %h = (a => 1, b => "two"); our $t = join "", 1 .. 3;
our @e = (); our %eh = (); our $hex = 0x10; our $negz = -0.0; our $inf = 9**9**9; our $uv = 18446744073709551615;
sub get { $n } sub bump { $n++; return } sub geth { $h{ $_[0] } } sub lcount { scalar @l } sub addl { push @l, $_[0]; return }
1;
