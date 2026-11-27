sub f { $_[1]->(); $_[0] } my $x = 1; my @l = (f($x, sub { $x = 5 }), f($x, sub { $x = 7 })); print "@l\n";
