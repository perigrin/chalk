my $r = [1,2,3]; { local @$r[0,1] = (8,9); print "@$r" } print "@$r\n";
