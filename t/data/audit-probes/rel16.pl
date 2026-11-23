my @a=(1,2,3); my @b; while (@a) { my $x=shift @a; unshift @b,$x; last if @b==2 } print "@a|@b\n";
