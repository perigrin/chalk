my @a=(1,2); sub z { $a[1]=7 } my $t=0; for my $x (@a) { z(); $t+=$x } print "$t\n";
