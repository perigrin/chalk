my @a = (1,2,3); my $i = 0; my @l = (@a[$i, $i+1] = (7, 8)); print "@l|@a\n";
