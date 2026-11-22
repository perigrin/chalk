our $g = 1; sub w { $g = 5; 0 } my $x = $g + w() + $g; print "$x\n";
