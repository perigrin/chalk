my @a = (1,2,3); my $r = \$a[0]; push @a, shift @a; $$r = 9; print "@a\n";
