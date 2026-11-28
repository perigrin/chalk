my @a = (3,1,2); my $r = \$a[0]; @a = reverse sort { $a <=> $b } @a; $$r = 9; print "@a\n";
