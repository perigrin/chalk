sub f { $_[1]->(); 0 } my $x = 1; my $y = $x + f($x, sub { $x = 5 }); print "$y\n";
