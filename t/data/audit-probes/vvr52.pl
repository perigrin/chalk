our @a = (1,2,3); my $r = \$a[1]; @a = reverse @a; $$r = 9; print "@a\n";
