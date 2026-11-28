my @a = (1,2,3); my $r = \$a[2]; splice(@a, 0, 2); $$r = 9; print "@a\n";
