my %h=(a=>"x", b=>"y"); %h = reverse %h; print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";
