my @a; print "e\n" if !@a; my $r = \@a; push @$r, 1; print scalar(@a), "\n";
