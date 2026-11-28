my @a = (3,2,1); my $r = \$a[0]; @a = sort { $a <=> $b } @a; $$r = 9; print "@a\n";
