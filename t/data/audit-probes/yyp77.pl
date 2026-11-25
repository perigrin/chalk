my @a=(1,2); my $r=\$a[0]; @a=(5,6); $$r=9; print "@a\n";
