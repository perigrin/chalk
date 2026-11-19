our $g = 0; sub bump { $g += 10 } if (@ARGV) { $g = 5 } else { $g = $g + 1; bump() } print "$g\n";
