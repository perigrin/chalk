my @a = (1,2,3); my $r = \$a[1]; splice(@a, 1, 0, 7); $$r = 9; print "@a\n";
