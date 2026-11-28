my $s = "k1=v1;k2=v2"; my %h = map { split /=/ } split /;/, $s; print join(",", map {"$_>$h{$_}"} sort keys %h), "\n";
