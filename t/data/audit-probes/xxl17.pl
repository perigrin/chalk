my @a = (0,0); my $r = \$a[0]; for my $i (1..4) { $$r += $i; $r = \$a[$i % 2] } print "@a\n";
