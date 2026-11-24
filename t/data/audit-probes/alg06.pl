my %h=(a=>1,b=>2); eval { for my $k (sort keys %h) { $h{$k} .= "!"; die "x\n" } }; print join(",", map { $h{$_} } sort keys %h), "\n";
