my @a = (3,1,2); my $first = (sort { $a <=> $b } @a)[0]; @a = (); print "$first\n";
