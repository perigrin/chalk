my @a=(1,2); sub z { $a[0]=7 } for my $x (@a[0,1]) { z(); print $x } print "\n";
