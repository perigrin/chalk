our $g = 0; sub bump { $g += 10 } my $v = $g = $g + 1; bump(); print "$v $g\n";
