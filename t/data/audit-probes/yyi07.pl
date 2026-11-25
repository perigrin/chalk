sub inc { $_[0]++ } my ($x,$y)=(1,5); inc($x || $y); print "$x $y\n";
