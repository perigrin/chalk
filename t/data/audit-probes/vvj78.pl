my @a = (1,2,3); my %h; @h{qw(a b c)} = @a; @a = (); print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
