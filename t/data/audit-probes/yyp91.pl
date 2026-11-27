my @a=(1); sub f { $a[0]=7; "" } my $s = ($a[0] = 5) . f(); print "$s\n";
