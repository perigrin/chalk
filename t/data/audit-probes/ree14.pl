my @a=(1,2,3); for my $i (0..$#a) { $a[$i]+= $a[$i-1] } print "@a\n";
