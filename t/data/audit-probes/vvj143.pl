my %h = (a=>1); my $r = \%h; my %c = %$r; $c{a} = 2; $r->{b} = 3; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
