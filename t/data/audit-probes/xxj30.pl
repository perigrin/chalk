my $s = "k=v;k2=v2"; my %h = $s =~ /(\w+)=(\w+)/g; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
