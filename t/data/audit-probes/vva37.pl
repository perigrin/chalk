our @a = (1,2); eval { local $a[0] = 5; die "z\n" }; print "@a$@";
