my @a=([1],[2]); sub z { $a[1]=[7] } for my $x (@a) { z(); print $x->[0] } print "\n";
