my @a=(1,2); my $r=\$a[0]; unshift @a, 0; $$r=9; print "@a\n";
