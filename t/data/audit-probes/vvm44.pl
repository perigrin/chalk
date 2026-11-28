our @a = (1,2,3); my $e = \$a[0]; { local @a = (3); $$e = 9; print "@a;" } print "@a\n";
