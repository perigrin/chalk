our $g = 0; sub bump { $g += 10 } $g = $g + 1; bump(); $g = $g + 1; bump(); print "$g\n";
