our @g = (1,2); my @r; sub show { push @r, join(",", @g) } for my $i (1..2) { show(); local $g[0] = "L"; show() } show(); print "@r\n";
