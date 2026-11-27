sub f { $_[1]->(); 0 } my $x = 1; my @l = ($x, f($x, sub { $x = 5 }), $x); print "@l\n";
