my %h = (1=>"a", "01"=>"b", 1.0=>"c", "1.0"=>"d"); print join(",", map {"$_$h{$_}"} sort keys %h), "\n";
