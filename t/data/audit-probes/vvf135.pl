my $x = 1; my $y = (sub { $_[0] })->($x, $x = 9); print "$y\n";
