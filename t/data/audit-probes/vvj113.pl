my %h = (a=>1,b=>2,c=>3); my %d = delete %h{qw(a b)}; print join(",", map {"$_$d{$_}"} sort keys %d), "|", join(",", keys %h), "\n";
