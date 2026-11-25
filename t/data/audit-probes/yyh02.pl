my $w; sub c { $w = wantarray ? "L" : defined(wantarray) ? "S" : "V"; 1 } c(); print $w; my $x = c(); print $w; my @y = c(); print "$w\n";
