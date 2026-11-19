my @q = (3); my @o; while (@q) { my $x = pop @q; push @o, $x; push @q, $x - 1 if $x > 1 } print "@o\n";
