my @a = (1,2,3); sub c { $a[0] = 9; 0 } my $s = $a[0] . c(); print "$s\n";
