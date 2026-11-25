our $i=7; sub w { $i=9 } my @a=(1,2); for $i (@a) { w() } print "$i @a\n";
