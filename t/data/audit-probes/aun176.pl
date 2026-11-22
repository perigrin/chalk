my @a = (1); my $x = (push @a, 2) . "@a" . (shift @a) . "@a"; print "$x\n";
