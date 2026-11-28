my @a = (1,2,3); for my $e ($a[1]) { shift @a; $e = 9 } print "@a\n";
