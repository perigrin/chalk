my @a=(1); sub w { push @a, 2; 0 } my @c = (@a, w(), @a); print "@c\n";
