my @a=(1,2,3); my $i=0; for my $x (@a) { $x=$a[$i+1]//0; $i++ } print "@a\n";
