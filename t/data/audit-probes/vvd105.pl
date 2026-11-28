my @a = (1,2,3); for my $e (@a[0,1] = (7,8)) { $e++ } print "@a\n";
