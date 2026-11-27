my @a=(1); sub f { $a[0]=7; 0 } my $n = ++$a[0] + f(); print "$n\n";
