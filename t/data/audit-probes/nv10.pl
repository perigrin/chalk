our @g = (1,2,3); my @r = reverse @g; my @s = map { $_ * 2 } @g; @g = (); print "@r|@s\n";
