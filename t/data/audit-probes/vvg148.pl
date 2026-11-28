my $x = [1]; my $y = $x; undef $x; print $y->[0], "\n";
