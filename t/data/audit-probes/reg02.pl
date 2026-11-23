our @a=(1); sub f { push @a,2; 0 } my @c=(@a, f(), @a); print "@c\n";
