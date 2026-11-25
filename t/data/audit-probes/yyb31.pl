my @a=(1,2); sub z { $a[1]=7 } for my $x (@a) { my $y=$x; z(); print $y, $x } print "\n";
