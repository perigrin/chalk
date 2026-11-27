my @a = (1,2); my $r = \@a; @$r = (); print scalar(@a), "\n";
