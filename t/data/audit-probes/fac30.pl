our @g=(1,2); sub f { local @g=@g; push @g,3; scalar @g } print f(), " ", scalar(@g), "\n";
