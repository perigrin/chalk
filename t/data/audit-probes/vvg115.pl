my $x = 1; sub wr { $x = $_[0] } my $o = $x; wr(5); print "$o$x\n";
