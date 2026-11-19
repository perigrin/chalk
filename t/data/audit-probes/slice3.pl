my %h = (a=>0); my @k = ("a","b"); @h{@k} = (7,8); print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";
