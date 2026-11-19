my %h = (a=>1); my $r = \%h; %h = (b=>2); print join(",", keys %$r), "\n";
