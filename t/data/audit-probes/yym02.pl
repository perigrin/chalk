my @s = sort (10, 9, 100, 1); my @n = sort { $a <=> $b } (10, 9, 100, 1); my @r = reverse sort { $a <=> $b } (10, 9, 100, 1); my @d = sort { $b cmp $a } qw(b a c); print "@s|@n|@r|@d\n";
