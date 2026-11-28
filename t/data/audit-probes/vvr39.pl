my @a = (1,2,3); for my $e (@a) { shift @a if $e == 1; $e *= 10 } print "@a\n";
