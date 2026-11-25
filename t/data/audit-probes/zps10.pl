my @a=("abc","def"); for my $x (@a) { substr($x,0,1,"z") } print "@a\n";
