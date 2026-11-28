my %h = (a=>1,b=>2); my %m = (c=>4, %h); %h = (); print join(",", map {"$_$m{$_}"} sort keys %m), scalar(%h) ? "t" : "f", "\n";
