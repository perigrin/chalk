our @g = (1, 2, 3); my $i = 0; while (@g) { shift @g; $i++ } print "$i\n";
