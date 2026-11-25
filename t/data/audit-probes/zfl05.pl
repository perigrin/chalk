my @a=(1,2,3); my @b=(@a, map { $_++ } @a); print "@b\n";
