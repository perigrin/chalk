my @a = (1,2); my @r; for my $i (1..2) { my @c = @a; push @r, "@c"; for (@a) { $_ .= "x" } } print "@r\n";
