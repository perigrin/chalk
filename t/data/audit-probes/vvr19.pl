my @a = (1,2,3); my $r = \$a[0]; my $p = shift @a; $$r = 9; print "$p@a\n";
