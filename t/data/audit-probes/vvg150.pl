my @a = ([1], [2]); my $f = shift @a; push @$f, 9; print "@$f|", scalar(@a), "\n";
