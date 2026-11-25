my %g; push @{ $g{length $_} }, $_ for qw(a bb cc d eee); print join(";", map { "$_=" . join(",", sort @{ $g{$_} }) } sort keys %g), "\n";
