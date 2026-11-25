my @a=(1,2,3,4,5); my @r=splice(@a,1,2); print "@r|@a|"; splice(@a,1,0,8,9); print "@a|"; splice(@a,-1); print "@a\n";
