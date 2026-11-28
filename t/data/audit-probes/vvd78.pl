my @a = (1,2,3); my $r = \@a[0,1]; $$r = 9; print "@a\n";
