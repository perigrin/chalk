my @a=(1,2); sub z { $a[0]=7 } for my $x (@a) { for my $y (@a) { z(); print "$x$y" } } print "\n";
