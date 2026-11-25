my @a=(1,2); my $y=9; for my $x (@a) { my @t=($y,$x); ($x,$y)=@t } print "@a $y\n";
