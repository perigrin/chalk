my @a=(1,2); my $y=9; for my $x (@a) { ($x,$y)=($y,$x) if $x==1 } print "@a $y\n";
