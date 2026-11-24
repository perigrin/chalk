my @a=(1,2,3,4); my @o; while (my ($x,$y)=splice(@a,0,2)) { push @o,$x+$y } print "@o\n";
