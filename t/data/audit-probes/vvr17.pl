my @a = (1,2,3); my $r = \$a[2]; pop @a; $$r = 9; print "@a|$$r\n";
