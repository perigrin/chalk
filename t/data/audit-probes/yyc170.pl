my @a=(1,2); my @b=(@a, map { $_ * 2 } @a); print "@b\n";
