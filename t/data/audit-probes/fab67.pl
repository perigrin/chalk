my @a=(1..5); my @b=@a[grep { $_ % 2 == 0 } 0..$#a]; print "@b\n";
