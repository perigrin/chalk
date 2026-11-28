our %h = (a=>1); my $r = \%h; { local %h = (b=>2); $r->{c} = 3 } print join(",", sort keys %h), "\n";
