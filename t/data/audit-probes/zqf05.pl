my @a=(1,2); my @b=(8,9); for my $x (@a) { ($x,@b)=(@b,$x) } print "@a|@b\n";
