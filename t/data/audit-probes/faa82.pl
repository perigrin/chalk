my @a=(1,2,3); my $l=\$a[0]; unshift @a,0; $$l=9; print "@a\n";
