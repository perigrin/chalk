my @a=(1); my @c=@a; sub w1 { $_[0][0]=2 } w1(\@c); print "$a[0]\n";
