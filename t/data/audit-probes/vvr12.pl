my @a = (1,2,3); my $r = \$a[1]; unshift @a, 0; $$r = 9; print "@a\n";
