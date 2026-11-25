sub by_num { $a <=> $b } my @s = sort by_num (3,1,2); my $cmp = sub { $b <=> $a }; my @t = sort $cmp (3,1,2); my @u = sort { by_num() } (9,8,7); print "@s|@t|@u\n";
