my @a=(1,2,3); my @b=(@a, scalar($a[0] =~ s/1/9/)); print "@b\n";
