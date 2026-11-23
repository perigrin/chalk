sub f { die "f\n" } my @a=(1); eval { push @a, f() }; print "@a $@";
