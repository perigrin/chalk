my @a = (1,2); my @r; my $i = 0; while ($i++ < 2) { push @r, join(",", @a); for (@a) { $_++ } } print "@r\n";
