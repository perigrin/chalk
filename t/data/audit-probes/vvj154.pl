my (%h, @a); $h{x} = \@a; push @{$h{x}}, 1; push @a, 2; print "@a\n";
