my $x = 1; my @o = (sub { $x = 5 }); sub f { $_->() for @o; $_[0] } print f($x), "\n";
