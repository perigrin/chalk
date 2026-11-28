my $x = 1; sub wr { $x = $_[0] } my $s = "$x"; wr(5); print "$s$x\n";
