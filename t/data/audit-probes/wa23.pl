our @g = (1,2); my $r = \@g; @g = (3); print "@$r\n";
