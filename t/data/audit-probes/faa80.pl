my ($x,$y)=(1,2); my @r=\($x,$y); ${$r[0]}=7; print "$x$y\n";
