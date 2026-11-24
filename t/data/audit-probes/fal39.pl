my @a; my $i=0; while (1) { push @a,$i; last if ++$i>2 } print "@a $i\n";
