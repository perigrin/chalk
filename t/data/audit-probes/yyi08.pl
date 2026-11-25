sub inc { $_[0]++ } my ($x,$y)=(0,5); inc($x || $y); print "$x $y\n";
