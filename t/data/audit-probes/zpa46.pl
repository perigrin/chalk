my @a=(1,2,3); my @m=map { $_*2 } @a; my @g=grep { $_++ } @a; print "@a|@m|@g\n";
