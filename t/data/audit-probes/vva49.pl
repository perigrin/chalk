our @a = (1,2); my $r = \@a; { local @a = (3); print "@$r" } print "@$r\n";
