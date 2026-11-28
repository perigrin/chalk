my @a = (1,2,3); my $r = \$a[1]; my @b = @a; $$r = 9; print "@a|@b\n";
