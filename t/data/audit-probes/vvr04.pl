my @a = (1,2,3); my $r = \$a[0]; my @b = reverse @a; $$r = 9; print "@a|@b\n";
