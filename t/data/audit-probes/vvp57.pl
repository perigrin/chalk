my @a = (1,2); my $c = sub { $a[-2] = 5 }; sub f { $_[1]->(); $_[0] } print f($a[0], $c), "\n";
