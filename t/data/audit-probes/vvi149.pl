my $s = "2024-01-15"; my ($y, $m, $d) = $s =~ /(\d+)-(\d+)-(\d+)/; my @p = split /-/, $s; print $y + $m + $d, "@p\n";
