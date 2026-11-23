my @a=(1,2,3); my $r=\$a[1]; $$r=8; print "@a\n"; shift @a; $$r=7; print "@a\n";
