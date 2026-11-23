my %h=(a=>1); my %c=%h; $c{a}=2; print "$h{a}$c{a}\n"; $h{a}=3; print "$h{a}$c{a}\n";
