my @a=(1,2,3); my @b=(@a, grep { $_++ } @a); print "@b\n";
