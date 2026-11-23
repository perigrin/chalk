our $g=1; sub f { $g=5; 1 } my $s = join(",", $g, f(), $g); print "$s\n";
