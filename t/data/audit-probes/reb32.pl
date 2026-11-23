my @a=(1,2,3); my $z=0; for my $e (@a) { $e = eval { 10/$z } // -1; $z++ } print "@a\n";
