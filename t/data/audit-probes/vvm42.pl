our @a = (1,2,3); my $r; { local @a = (3); $r = \@a; } print "@$r|@a\n";
