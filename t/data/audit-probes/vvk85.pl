my $n = 0; my @a = (1, 2, 3); for my $e (@a, ()) { $e++ } for my $e (grep { 1 } @a) { $e++ } print "@a\n";
