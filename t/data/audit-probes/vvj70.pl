my @a = (1,2); my @b = (3,4); my $s = ""; for my $e (@a) { for my $f (@b) { $f += $e; $e++ } } print "@a|@b\n";
