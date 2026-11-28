my @a = (1,2,3); my $r = \$a[1]; push @a, (0) x 100; $$r = 9; print "@a[0..2]\n";
