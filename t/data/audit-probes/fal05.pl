my @a=(1,2,3); my $s=0; for my $i (0..$#a) { $a[$i]+=$s; $s=$a[$i] } print "@a\n";
