my @a=(1,2,3); sub z { $a[2]=10 } my $t=0; for my $x (@a) { $t+=$x; z(); } print "$t\n";
