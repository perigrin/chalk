my $s = "hello"; my %c; $c{$_}++ for split //, $s; print join("", map {"$_$c{$_}"} sort keys %c), "\n";
