my $z=0; my @a=(1,2); eval { $a[0] = 9; my $unused = 1 / $z; $a[1] = 9; }; print "@a\n";
