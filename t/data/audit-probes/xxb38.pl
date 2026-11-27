my @a=(1,2,3); my $n = 0; for my $x (@a) { $n += $x; shift @a if $n == 1 } print "$n @a\n";
