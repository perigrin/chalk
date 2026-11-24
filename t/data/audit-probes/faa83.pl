my @a=(1,2,3); my $l=\$a[1]; splice(@a,0,1); $$l=9; print "@a\n";
