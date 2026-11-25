my @a=(1,2); sub f { return @a } my @c=f(); push @a,3; print "@c\n";
