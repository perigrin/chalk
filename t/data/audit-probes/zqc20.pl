my @a=(1,2); sub z { $a[1]=7; 0 } for my $x (@a) { my $v=$x+z(); print $v } print "\n";
