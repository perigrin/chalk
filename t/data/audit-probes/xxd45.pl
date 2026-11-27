my %h = (a=>1); my $r = \%h; my %c = %$r; $r->{b} = 2; print join(",", sort keys %h), "|", join(",", sort keys %c), "\n";
