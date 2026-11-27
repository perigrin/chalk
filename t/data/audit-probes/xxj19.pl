my $s = "abc"; my @seen; $s =~ s/(.)/push @seen, $1; ""/ge; print "@seen|$s|\n";
