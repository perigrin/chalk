my @a=(1,2); sub w { $a[0]=9 } my $j=join(",",@a); w(); print "$j\n";
