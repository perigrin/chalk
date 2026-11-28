my @a = (1,2,3); my @m = map { $_ * 2 } (@a[0,1] = (7, 8)); print "@m|@a\n";
