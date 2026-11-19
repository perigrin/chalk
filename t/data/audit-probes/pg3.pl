our $g = 0; sub bump { $g += 10 } my $i = 0; while ($i++ < 3) { $g++; bump() if $i == 2; $g *= 2 } print "$g\n";
