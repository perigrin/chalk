my @a=(1,2); sub d { $_[0]=9; die "a\n" } eval { d($a[0]) }; print "@a\n";
