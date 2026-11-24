my @a=(1,2); sub w { $a[0]=9 } my $s="@a"; w(); print "$s\n";
