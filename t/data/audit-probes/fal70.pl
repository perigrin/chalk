my @a=(1,2,3); my $i=0; for my $x (@a) { $a[$i+1]+=$x if $i<2; $i++ } print "@a\n";
