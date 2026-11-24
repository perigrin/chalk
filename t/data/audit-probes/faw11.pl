my @a=(1,2); my ($x,$y); sub sw { ($x,$y)=@a; @a=($y,$x) } sw(); sw(); sw(); print "@a $x\n";
