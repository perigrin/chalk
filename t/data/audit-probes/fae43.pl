my @a=(1,2,3); eval { shift @a; die "a\n" }; print "@a\n";
