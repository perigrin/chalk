my @a=(1,2); for my $x (@a) { my ($p,$q)=($x,$x); ($x,$p)=($p+$q,0) } print "@a\n";
