my @a=(1,2); my $y=9; for my $x (@a) { ($x,$y)=($y,$x) } print "@a $y\n";
