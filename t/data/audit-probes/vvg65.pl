my %g; push @{$g{$_ % 2}}, $_ for 1..5; print join("|", map { "@{$g{$_}}" } sort keys %g), "\n";
