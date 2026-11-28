my @a = (1,2,3); my $r = \@a; @$r = (); print scalar(@a), "\n";
