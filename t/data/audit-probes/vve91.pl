my @a = (1,2); my $r = \@a; sub f { $r->[0] = 5; $_[0] } print f($a[0]), "\n";
