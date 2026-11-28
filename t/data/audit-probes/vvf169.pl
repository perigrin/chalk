my $r = [1]; my $keep = $r; sub c { $r = [9]; 0 } my @l = ($r->[0], c(), $r->[0]); print "@l\n";
