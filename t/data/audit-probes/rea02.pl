my @a=(1,2,3); my $s=0; for my $x (@a) { last if $x==2; $x=9; $s++ } print "@a $s\n";
