sub set { $_[0] = "s" } my ($x,$y,$c)=(1,2,0); set($c ? $x : $y); set($c ? $x : $y, 0) for 1..2; print "$x$y\n";
