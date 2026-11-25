my @a=(1); sub f { $a[0]=9; 1 } my $n = $a[0] + f(); print "$n\n";
