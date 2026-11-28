our %h = (a=>1); my $r = \%h; { local %h = (b=>2); print join(",", keys %$r) } print join(",", keys %$r), "\n";
