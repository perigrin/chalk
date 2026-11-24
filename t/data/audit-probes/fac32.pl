my @a=(1); for (1..3) { my @b=@a; push @b,$_; @a=@b } print "@a\n";
