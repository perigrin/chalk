my @a=(1,2); for my $x (@a) { eval { $x++ } } print "@a\n";
