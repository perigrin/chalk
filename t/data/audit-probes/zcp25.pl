my @a=(1,2); sub f { \@a } my @c=@{f()}; push @a,3; print "@c\n";
