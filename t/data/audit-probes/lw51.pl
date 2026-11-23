my @a = (1,2); my @r; sub f { return @_ } for my $i (1..2) { push @r, join(",", f(@a)); for (@a) { $_ .= "x" } } print "@r\n";
