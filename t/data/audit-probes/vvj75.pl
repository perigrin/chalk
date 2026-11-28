my @a = (1,2,3); my @b = @a[grep { $_ != 1 } 0..$#a]; print "@b\n";
