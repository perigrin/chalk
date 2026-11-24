my @a=(1,2); sub g { $a[0]=5; 0 } my $v = $a[0] + g(); print "$v\n";
