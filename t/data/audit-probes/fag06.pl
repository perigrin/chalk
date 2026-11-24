my @a=(1,2); sub w { $a[0]=9 } my @c=@a; my $n=@c; w(); print "$n $c[0]\n";
