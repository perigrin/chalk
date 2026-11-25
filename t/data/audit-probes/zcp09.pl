my %h=(a=>1); my %c=%h; $h{a}=2; $h{b}=3; print join(",", map { "$_$c{$_}" } sort keys %c), "\n";
