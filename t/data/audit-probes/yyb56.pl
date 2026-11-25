my @a=(1,2); my $i=0; for my $x (@a) { $a[$i+1 < @a ? $i+1 : 0] = 7; $i++; print $x } print "\n";
