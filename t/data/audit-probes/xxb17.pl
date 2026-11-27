my %h=(a=>1,b=>2); $_++ for @h{qw(a b c)}; print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
