my %h = (a=>1); my $r = \%h; $r->{b} = 2; print join(",", sort keys %h), "\n";
