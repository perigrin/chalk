my @a = (1,2,3); my $r = \$a[1]; @a = grep { 1 } @a; $$r = 9; print "@a\n";
