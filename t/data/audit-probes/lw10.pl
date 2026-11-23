sub bump { $_[0] .= "x" } my @a = (1,2); my @r; for my $i (1..2) { push @r, join(",", @a); for my $e (@a) { bump($e) } } print "@r\n";
