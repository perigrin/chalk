my @a=(1,2); sub z { $a[1]=7 } for my $i (0..1) { z(); print $a[$i] } print "\n";
