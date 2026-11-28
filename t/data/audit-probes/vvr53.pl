our @a = (1,2,3); my $r = \$a[1]; shift @a; $$r = 9; print "@a\n";
