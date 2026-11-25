our @a=(1,2); sub f { local @a=@a; push @a,3; scalar @a } print f(), scalar(@a), "\n";
