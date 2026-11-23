my %h=(a=>1); my $r=\%h; $r->{b}=2; print join(",", map {"$_=$h{$_}"} sort keys %h), "\n";
