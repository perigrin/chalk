my @a=(1,2,3); sub z { $a[2]=7 } for my $i (0..$#a) { z(); print $a[$i] } print "\n";
