my ($x,$y)=(1,1); my $z = ($x ||= 5) + ($y &&= 7); print "$x$y$z\n";
