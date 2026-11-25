my @a=(1,2,3); my @b=@a[grep { $_ != 1 } 0..$#a]; my @c=(@a)[1..$#a]; my @d=@a[-2,-1]; print "@b|@c|@d\n";
