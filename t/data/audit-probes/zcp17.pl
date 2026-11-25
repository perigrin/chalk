my %h=(a=>1); my $r={%h}; $h{a}=9; $h{b}=1; print join(",", map { "$_$r->{$_}" } sort keys %$r), "\n";
