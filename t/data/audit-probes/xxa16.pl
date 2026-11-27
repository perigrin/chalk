sub f { $_[0] = 5; 1 } my $x=1; my $y = $x + f($x); print "$x $y\n";
