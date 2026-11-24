my @a=(1,2); sub w { $a[0]=9 } my ($x,$y)=@a; w(); print "$x$y\n";
